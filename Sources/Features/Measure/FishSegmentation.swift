import Vision
import CoreVideo
import CoreGraphics
import simd

/// 使用 iOS 17 的前景分割自動偵測魚體,並以 PCA 主軸找出最長軸兩端點。
/// 回傳座標為 capturedImage 的「像素座標」(原點左上)。
struct FishSegmentation {

    struct Result {
        let p1: CGPoint          // 主軸一端(像素座標)
        let p2: CGPoint          // 主軸另一端
        let maskAreaRatio: CGFloat // 遮罩面積佔畫面比例(用於有效性過濾)
    }

    /// 遮罩面積佔比的有效範圍:太小=沒對到魚,太大=鏡頭貼太近或誤判整個地面
    static let validAreaRange: ClosedRange<CGFloat> = 0.03...0.70

    /// 對單一影格執行分割 + 端點計算。應在背景佇列呼叫。
    static func detectEndpoints(in pixelBuffer: CVPixelBuffer,
                                orientation: CGImagePropertyOrientation) -> Result? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return nil }

        // 產生與輸入影像同尺寸的遮罩(單通道 Float)
        guard let mask = try? observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler) else { return nil }

        return endpointsFromMask(mask)
    }

    /// 對遮罩像素做 PCA:
    /// 1. 以 stride 下採樣收集前景點
    /// 2. 計算共變異矩陣的主軸方向
    /// 3. 沿主軸投影取最遠兩點 → 魚的吻端與尾端
    private static func endpointsFromMask(_ mask: CVPixelBuffer) -> Result? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }

        // 遮罩為 Float32 單通道
        let stride = max(2, min(width, height) / 200)  // 下採樣,控制點數量
        var points: [SIMD2<Double>] = []
        points.reserveCapacity(4096)

        for y in Swift.stride(from: 0, to: height, by: stride) {
            let row = base.advanced(by: y * bytesPerRow)
                          .assumingMemoryBound(to: Float32.self)
            for x in Swift.stride(from: 0, to: width, by: stride) {
                if row[x] > 0.5 {
                    points.append(SIMD2(Double(x), Double(y)))
                }
            }
        }

        guard points.count > 30 else { return nil }

        // 面積佔比(以取樣密度換算)
        let sampledTotal = (width / stride) * (height / stride)
        let areaRatio = CGFloat(points.count) / CGFloat(max(sampledTotal, 1))
        guard validAreaRange.contains(areaRatio) else { return nil }

        // 均值
        var mean = SIMD2<Double>(0, 0)
        for p in points { mean += p }
        mean /= Double(points.count)

        // 2x2 共變異
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for p in points {
            let d = p - mean
            sxx += d.x * d.x
            sxy += d.x * d.y
            syy += d.y * d.y
        }
        let n = Double(points.count)
        sxx /= n; sxy /= n; syy /= n

        // 主軸角度(closed-form 2x2 特徵向量)
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let axis = SIMD2<Double>(cos(theta), sin(theta))

        // 沿主軸投影找最遠兩點
        var minT = Double.greatestFiniteMagnitude
        var maxT = -Double.greatestFiniteMagnitude
        var pMin = mean, pMax = mean
        for p in points {
            let t = simd_dot(p - mean, axis)
            if t < minT { minT = t; pMin = p }
            if t > maxT { maxT = t; pMax = p }
        }

        return Result(p1: CGPoint(x: pMin.x, y: pMin.y),
                      p2: CGPoint(x: pMax.x, y: pMax.y),
                      maskAreaRatio: areaRatio)
    }
}
