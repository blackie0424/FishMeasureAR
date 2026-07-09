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

    /// 浮水印(日期/地點;長度標籤由 ImageAnnotator 於量測位置合成)
    /// + EXIF + 相簿。回傳 PHAsset localIdentifier。
    /// 授權對話框等待不設限;寫入相簿本身 15 秒逾時,不讓 UI 永久卡死。
    func save(image: UIImage,
              location: CLLocation?,
              placeName: String?) async throws -> String {

        logger.info("save: start (\(Int(image.size.width))x\(Int(image.size.height)))")
        let settings = AppSettings()
        let final = settings.watermarkEnabled
            ? addWatermark(to: image,
                           placeName: settings.watermarkShowsPlace ? placeName : nil)
            : image
        logger.info("save: watermark done")

        // 依隱私設定決定寫入的座標(模糊化或原始)
        let gpsLocation: CLLocation? = {
            guard let location, settings.embedGPSInPhoto else { return nil }
            return settings.fuzzLocation ? location.fuzzed() : location
        }()

        let data = try encodeJPEGWithMetadata(final, location: gpsLocation)
        logger.info("save: jpeg encoded (\(data.count) bytes)")

        // 授權(可能跳系統對話框,等多久都合理,不設逾時)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        logger.info("save: photo auth = \(status.rawValue)")
        guard status == .authorized || status == .limited else {
            throw CaptureError.photoLibraryDenied
        }

        // 寫入相簿:15 秒逾時保護
        let localID = try await withTimeout(seconds: 15) {
            try await Self.writeToPhotoLibrary(data)
        }
        logger.info("save: done, localID=\(localID)")
        return localID
    }

    /// 兩個子任務賽跑:操作 vs 逾時;逾時先到就丟 timedOut。
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CaptureError.timedOut
            }
            guard let result = try await group.next() else {
                throw CaptureError.timedOut
            }
            group.cancelAll()
            return result
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

    // MARK: PhotoKit

    private static func writeToPhotoLibrary(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var localID = ""
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                localID = request.placeholderForCreatedAsset?.localIdentifier ?? ""
            }) { success, error in
                if success { cont.resume(returning: localID) }
                else { cont.resume(throwing: error ?? CaptureError.encodeFailed) }
            }
        }
    }
}

extension CLLocation {
    /// 釣點隱私:座標四捨五入至小數 2 位(約 ±1km)
    func fuzzed() -> CLLocation {
        CLLocation(latitude: (coordinate.latitude * 100).rounded() / 100,
                   longitude: (coordinate.longitude * 100).rounded() / 100)
    }
}
