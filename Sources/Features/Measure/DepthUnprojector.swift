import ARKit
import simd

/// 將 capturedImage 像素座標 + LiDAR 深度圖反投影為世界座標。
/// 針對濕滑魚體反光造成的深度噪點,端點深度取 5x5 鄰域中位數。
struct DepthUnprojector {

    /// - Parameters:
    ///   - pixel: capturedImage 像素座標(原點左上)
    ///   - frame: 當前 ARFrame(需含 sceneDepth)
    /// - Returns: 世界座標(公尺),失敗回傳 nil
    static func unproject(pixel: CGPoint, frame: ARFrame) -> SIMD3<Float>? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            return nil
        }
        let depthMap = depthData.depthMap

        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        // capturedImage → 深度圖座標縮放(深度圖通常為 256x192)
        let dx = Int(pixel.x * CGFloat(depthWidth) / CGFloat(imageWidth))
        let dy = Int(pixel.y * CGFloat(depthHeight) / CGFloat(imageHeight))

        guard let depth = medianDepth(at: dx, dy, in: depthMap,
                                      width: depthWidth, height: depthHeight),
              depth > 0.05, depth < 5.0 else { return nil }

        // 相機內參(對應 capturedImage 解析度)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0], fy = intrinsics[1][1]
        let cx = intrinsics[2][0], cy = intrinsics[2][1]

        // 影像座標 → 相機空間(ARKit 相機:+x 右、+y 上、-z 前方)
        let localX = (Float(pixel.x) - cx) * depth / fx
        let localY = -(Float(pixel.y) - cy) * depth / fy
        let localZ = -depth
        let local = SIMD4<Float>(localX, localY, localZ, 1)

        let world = frame.camera.transform * local
        return SIMD3(world.x, world.y, world.z)
    }

    /// 5x5 鄰域深度中位數,剔除無效值(0 / NaN)
    private static func medianDepth(at x: Int, _ y: Int,
                                    in depthMap: CVPixelBuffer,
                                    width: Int, height: Int) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        var samples: [Float] = []
        samples.reserveCapacity(25)
        for oy in -2...2 {
            let sy = y + oy
            guard sy >= 0, sy < height else { continue }
            let row = base.advanced(by: sy * bytesPerRow)
                          .assumingMemoryBound(to: Float32.self)
            for ox in -2...2 {
                let sx = x + ox
                guard sx >= 0, sx < width else { continue }
                let d = row[sx]
                if d.isFinite && d > 0 { samples.append(d) }
            }
        }
        guard samples.count >= 5 else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }
}
