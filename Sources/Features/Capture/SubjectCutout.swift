import Vision
import UIKit
import CoreImage
import os

/// 拍攝物前景切割(全幅對齊):把照片裡的主體(魚)切出成透明背景圖,
/// 疊回照片最上層 → 量魚板等參照物視覺上「墊在拍攝物下方」,
/// 可直接從板上刻度讀出拍攝物的位置與長度。
/// 與 ReferenceCutout 同技術,但保留全幅座標(不裁切),疊回時像素對齊。
enum SubjectCutout {

    private static let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                       category: "cutout")

    static func extract(from image: UIImage) async -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg)
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first,
                  !observation.allInstances.isEmpty,
                  let buffer = try? observation.generateMaskedImage(
                      ofInstances: observation.allInstances,
                      from: handler,
                      croppedToInstancesExtent: false) else {
                logger.warning("subject cutout failed, overlay will stay on top")
                return nil
            }
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let output = context.createCGImage(ciImage,
                                                     from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        }.value
    }
}
