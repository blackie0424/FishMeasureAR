import RealityKit
import UIKit
import Photos
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

enum CaptureError: Error {
    case snapshotFailed
    case encodeFailed
    case photoLibraryDenied
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

    /// 浮水印 + EXIF + 相簿。回傳 PHAsset localIdentifier。
    func save(image: UIImage,
              lengthCM: Double?,
              location: CLLocation?,
              placeName: String?) async throws -> String {

        let settings = AppSettings()
        let final = settings.watermarkEnabled
            ? addWatermark(to: image, lengthCM: lengthCM,
                           placeName: settings.watermarkShowsPlace ? placeName : nil)
            : image

        // 依隱私設定決定寫入的座標(模糊化或原始)
        let gpsLocation: CLLocation? = {
            guard let location, settings.embedGPSInPhoto else { return nil }
            return settings.fuzzLocation ? location.fuzzed() : location
        }()

        let data = try encodeJPEGWithMetadata(final, location: gpsLocation)
        return try await saveToPhotoLibrary(data)
    }

    // MARK: 浮水印

    private func addWatermark(to image: UIImage, lengthCM: Double?, placeName: String?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)

            let dateStr = DateFormatter.localizedString(from: .now,
                                                        dateStyle: .medium,
                                                        timeStyle: .short)
            var lines = [String]()
            if let lengthCM { lines.append(String(format: "%.1f cm", lengthCM)) }
            lines.append(dateStr)
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

    private func saveToPhotoLibrary(_ data: Data) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CaptureError.photoLibraryDenied
        }

        return try await withCheckedThrowingContinuation { cont in
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
