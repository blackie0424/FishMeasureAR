import RealityKit
import UIKit
import Photos
import ImageIO
import CoreLocation
import UniformTypeIdentifiers
import os

enum CaptureError: Error {
    case snapshotFailed
    case encodeFailed
    case photoLibraryDenied
    case timedOut
}

/// 相簿儲存選項:設定值一律在 MainActor 先讀好再傳入,
/// 服務本體不碰 @AppStorage(SwiftUI 包裝器不保證非主執行緒安全)。
struct PhotoSaveOptions: Sendable {
    let watermarkEnabled: Bool
    /// nil = 浮水印不顯示地點
    let watermarkPlace: String?
    /// 寫入 EXIF 的座標(已含隱私模糊化處理);nil = 不寫入
    let gpsLocation: CLLocation?
}

/// 一組漁獲照片的儲存結果
struct PhotoSaveResult {
    /// 縮圖用主照片(測量版優先)
    let primaryID: String
    /// 依序:原圖、測量版、比例物版(存在者)
    let allIDs: [String]
}

/// 拍攝服務:AR 快照、浮水印合成 → 寫入 EXIF GPS → 存入相簿
final class CaptureService {

    /// AR 畫面快照(工作流「凍結」當前影像用)
    @MainActor
    func snapshot(from arView: ARView) async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            arView.snapshot(saveToHDR: false) { image in
                if let image { cont.resume(returning: image) }
                else { cont.resume(throwing: CaptureError.snapshotFailed) }
            }
        }
    }

    private let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                category: "capture")

    /// 專屬相簿名稱:所有拍攝成果集中於此
    static let albumTitle = "FishMeasureAR"

    /// 一次儲存一組漁獲照片(最多三張)到「FishMeasureAR」相簿:
    /// 1. 原圖(乾淨無合成,只帶 EXIF)
    /// 2. 含測量線與長度(套浮水印設定)
    /// 3. 原圖+比例物疊圖(套浮水印設定;未選比例物則略過)
    /// 回傳整組 localIdentifier(依序:原圖/測量版/比例物版),
    /// primaryID 為量測版(無則原圖),供日誌/統計縮圖使用。
    /// 授權對話框等待不設限;寫入相簿本身 20 秒逾時,不讓 UI 永久卡死。
    func saveCatchPhotos(original: UIImage,
                         measured: UIImage?,
                         reference: UIImage?,
                         options: PhotoSaveOptions) async throws -> PhotoSaveResult {

        logger.info("save: start (original + measured=\(measured != nil) + reference=\(reference != nil))")

        func watermarked(_ image: UIImage) -> UIImage {
            options.watermarkEnabled
                ? addWatermark(to: image, placeName: options.watermarkPlace)
                : image
        }

        var items: [Data] = []
        items.append(try encodeJPEGWithMetadata(original, location: options.gpsLocation))
        var primaryIndex = 0
        if let measured {
            items.append(try encodeJPEGWithMetadata(watermarked(measured),
                                                    location: options.gpsLocation))
            primaryIndex = items.count - 1
        }
        if let reference {
            items.append(try encodeJPEGWithMetadata(watermarked(reference),
                                                    location: options.gpsLocation))
        }
        logger.info("save: encoded \(items.count) photos")

        // 授權(可能跳系統對話框,等多久都合理,不設逾時)。
        // 建相簿需要 readWrite;若僅授權「加入照片」則退回無相簿的散存。
        let rwStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        logger.info("save: photo auth(readWrite) = \(rwStatus.rawValue)")
        var album: PHAssetCollection?
        if rwStatus == .authorized {
            album = try? await Self.fetchOrCreateAlbum(named: Self.albumTitle)
            if album == nil { logger.warning("save: album unavailable, saving without") }
        } else if rwStatus != .limited {
            let addStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard addStatus == .authorized || addStatus == .limited else {
                throw CaptureError.photoLibraryDenied
            }
        }

        // 寫入相簿:20 秒逾時保護(一個交易寫入整組)
        let itemsToWrite = items
        let targetAlbum = album
        let idx = primaryIndex
        let result = try await withTimeout(seconds: 20) {
            try await Self.writeSet(itemsToWrite, primaryIndex: idx, album: targetAlbum)
        }
        logger.info("save: done, \(result.allIDs.count) photos, primary=\(result.primaryID)")
        return result
    }

    /// 找到或建立專屬相簿(需 readWrite 完整授權)
    private static func fetchOrCreateAlbum(named title: String) async throws -> PHAssetCollection? {
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album,
                                                            subtype: .albumRegular,
                                                            options: nil)
        var found: PHAssetCollection?
        fetch.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == title {
                found = collection
                stop.pointee = true
            }
        }
        if let found { return found }

        var placeholderID = ""
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: title)
            placeholderID = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        return PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [placeholderID], options: nil).firstObject
    }

    /// 單一交易寫入整組照片並加入相簿;回傳整組 localIdentifier
    private static func writeSet(_ items: [Data],
                                 primaryIndex: Int,
                                 album: PHAssetCollection?) async throws -> PhotoSaveResult {
        var primaryID = ""
        var allIDs: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            var placeholders: [PHObjectPlaceholder] = []
            for data in items {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                }
            }
            allIDs = placeholders.map(\.localIdentifier)
            if placeholders.indices.contains(primaryIndex) {
                primaryID = placeholders[primaryIndex].localIdentifier
            }
            if let album,
               let change = PHAssetCollectionChangeRequest(for: album) {
                change.addAssets(placeholders as NSArray)
            }
        }
        guard !primaryID.isEmpty else { throw CaptureError.encodeFailed }
        return PhotoSaveResult(primaryID: primaryID, allIDs: allIDs)
    }

    /// 先到先贏的逾時:不能用 TaskGroup——group 會等所有子任務結束,
    /// 而相簿寫入不可取消,一旦寫入卡住,逾時分支根本救不出 UI。
    /// 改為 continuation 由先完成者 resume,遲到者被旗標擋掉。
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func claimFirst() -> Bool {
                resumed.withLock { already in
                    if already { return false }
                    already = true
                    return true
                }
            }
            Task {
                do {
                    let value = try await operation()
                    if claimFirst() { cont.resume(returning: value) }
                } catch {
                    if claimFirst() { cont.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if claimFirst() { cont.resume(throwing: CaptureError.timedOut) }
            }
        }
    }

    // MARK: 浮水印

    private func addWatermark(to image: UIImage, placeName: String?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)

            let dateStr = DateFormatter.localizedString(from: .now,
                                                        dateStyle: .medium,
                                                        timeStyle: .short)
            var lines = [dateStr]
            if let placeName { lines.append(placeName) }

            let fontSize = image.size.width * 0.035
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black.withAlphaComponent(0.6),
                .strokeWidth: -3.0,
            ]

            var y = image.size.height - CGFloat(lines.count) * fontSize * 1.4 - 24
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 24, y: y), withAttributes: attrs)
                y += fontSize * 1.4
            }
        }
    }

    // MARK: EXIF GPS

    private func encodeJPEGWithMetadata(_ image: UIImage, location: CLLocation?) throws -> Data {
        guard let cgImage = image.cgImage else { throw CaptureError.encodeFailed }

        var metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: exifDateString(.now)
            ]
        ]
        if let location {
            metadata[kCGImagePropertyGPSDictionary] = gpsDictionary(for: location)
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData,
                                                          UTType.jpeg.identifier as CFString,
                                                          1, nil) else {
            throw CaptureError.encodeFailed
        }
        CGImageDestinationAddImage(dest, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.encodeFailed }
        return data as Data
    }

    private func gpsDictionary(for location: CLLocation) -> [CFString: Any] {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return [
            kCGImagePropertyGPSLatitude: abs(lat),
            kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(lon),
            kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W",
            kCGImagePropertyGPSAltitude: location.altitude,
            kCGImagePropertyGPSTimeStamp: gpsTimeString(location.timestamp),
        ]
    }

    private func exifDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.string(from: date)
    }

    private func gpsTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

}

extension CLLocation {
    /// 釣點隱私:座標四捨五入至小數 2 位(約 ±1km)
    func fuzzed() -> CLLocation {
        CLLocation(latitude: (coordinate.latitude * 100).rounded() / 100,
                   longitude: (coordinate.longitude * 100).rounded() / 100)
    }
}
