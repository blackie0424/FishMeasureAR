import Vision
import UIKit
import CoreImage
import os

/// 參照物圖片去背:Vision 前景分割(與量魚同一套技術),
/// 首次載入時計算並快取;去背失敗時退回原圖。
@MainActor
enum ReferenceCutout {

    private static var cache: [String: UIImage] = [:]
    private static let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                       category: "cutout")

    static func load(named name: String) async -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let source = UIImage(named: name), let cg = source.cgImage else {
            logger.error("cutout: asset '\(name)' not found")
            return nil
        }

        let cutout = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg)
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first,
                  !observation.allInstances.isEmpty,
                  let buffer = try? observation.generateMaskedImage(
                      ofInstances: observation.allInstances,
                      from: handler,
                      croppedToInstancesExtent: true) else { return nil }

            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let output = context.createCGImage(ciImage,
                                                     from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        }.value

        if cutout == nil {
            logger.warning("cutout: segmentation failed for '\(name)', using original")
        }
        let final = cutout ?? source
        cache[name] = final
        return final
    }
}
