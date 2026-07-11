import UIKit

/// 把長度標籤(黑底膠囊+白字)畫進照片。
/// 量測線本身是 RealityKit 3D 實體,ARView 快照已包含,這裡只補標籤。
enum ImageAnnotator {

    /// 把參照物疊圖(已去背)畫進照片:
    /// 以長邊等比縮放到 longSidePx(對應實際 cm/px),中心對齊指定點,
    /// 可繞中心旋轉(與編輯畫面同角度,所見即所得)。
    static func drawOverlay(_ overlay: UIImage,
                            centeredAt center: CGPoint,
                            longSidePx: CGFloat,
                            rotationDegrees: Double = 0,
                            on image: UIImage) -> UIImage {
        let longSide = max(overlay.size.width, overlay.size.height)
        guard longSide > 0, longSidePx > 0 else { return image }
        let scale = longSidePx / longSide
        let size = CGSize(width: overlay.size.width * scale,
                          height: overlay.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: CGFloat(rotationDegrees) * .pi / 180)
            overlay.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                    width: size.width, height: size.height))
            cg.restoreGState()
        }
    }

    /// 量魚/比例尺路徑用:照片上沒有 3D 線段,把量測線+端點+標籤一起畫上。
    static func drawMeasurement(from p1: CGPoint, to p2: CGPoint,
                                label: String, labelAt labelPoint: CGPoint,
                                rotationDegrees: Int = 0,
                                on image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let withLine = renderer.image { _ in
            image.draw(at: .zero)

            // 亮青色主線(與 AR 畫面同色)+ 較粗深色底線,任何背景都清楚
            let lineWidth = max(image.size.width * 0.008, 4)
            let cyan = UIColor(red: 0.21, green: 0.77, blue: 0.94, alpha: 1)

            let underPath = UIBezierPath()
            underPath.move(to: p1)
            underPath.addLine(to: p2)
            underPath.lineWidth = lineWidth * 1.7
            underPath.lineCapStyle = .round
            UIColor.black.withAlphaComponent(0.55).setStroke()
            underPath.stroke()

            let path = UIBezierPath()
            path.move(to: p1)
            path.addLine(to: p2)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            cyan.setStroke()
            path.stroke()

            // 端點:白心圓 + 青色外框(同確認頁樣式)
            let r = lineWidth * 1.8
            for p in [p1, p2] {
                let dot = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r,
                                                      width: r * 2, height: r * 2))
                UIColor.white.setFill()
                dot.fill()
                dot.lineWidth = lineWidth * 0.6
                cyan.setStroke()
                dot.stroke()
            }
        }
        return drawLengthLabel(label, at: labelPoint,
                               rotationDegrees: rotationDegrees, on: withLine)
    }

    /// - Parameter rotationDegrees: 標籤繞自身中心旋轉(橫向拍攝時 90/270,
    ///   與螢幕氣泡的 rotationEffect 同角度,所見即所得)
    static func drawLengthLabel(_ text: String,
                                at point: CGPoint,
                                rotationDegrees: Int = 0,
                                on image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)

            let fontSize = image.size.width * 0.045
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let padH = fontSize * 0.6, padV = fontSize * 0.35
            let labelSize = CGSize(width: textSize.width + padH * 2,
                                   height: textSize.height + padV * 2)

            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: point.x, y: point.y)
            cg.rotate(by: CGFloat(rotationDegrees) * .pi / 180)

            // 以旋轉後的原點為中心繪製
            let rect = CGRect(x: -labelSize.width / 2, y: -labelSize.height / 2,
                              width: labelSize.width, height: labelSize.height)
            let capsule = UIBezierPath(roundedRect: rect,
                                       cornerRadius: rect.height / 2)
            UIColor.black.withAlphaComponent(0.65).setFill()
            capsule.fill()
            (text as NSString).draw(
                at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                withAttributes: attrs)
            cg.restoreGState()
        }
    }
}
