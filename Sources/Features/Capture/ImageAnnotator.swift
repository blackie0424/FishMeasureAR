import UIKit

/// 把長度標籤(黑底膠囊+白字)畫進照片。
/// 量測線本身是 RealityKit 3D 實體,ARView 快照已包含,這裡只補標籤。
enum ImageAnnotator {

    /// 量魚/比例尺路徑用:照片上沒有 3D 線段,把量測線+端點+標籤一起畫上。
    static func drawMeasurement(from p1: CGPoint, to p2: CGPoint,
                                label: String, labelAt labelPoint: CGPoint,
                                on image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let withLine = renderer.image { _ in
            image.draw(at: .zero)

            let lineWidth = max(image.size.width * 0.004, 2)
            let path = UIBezierPath()
            path.move(to: p1)
            path.addLine(to: p2)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            UIColor.white.setStroke()
            path.stroke()

            let r = lineWidth * 2.2
            for p in [p1, p2] {
                let dot = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r,
                                                      width: r * 2, height: r * 2))
                UIColor.white.setFill()
                dot.fill()
            }
        }
        return drawLengthLabel(label, at: labelPoint, on: withLine)
    }

    static func drawLengthLabel(_ text: String,
                                at point: CGPoint,
                                on image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(at: .zero)

            let fontSize = image.size.width * 0.045
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let padH = fontSize * 0.6, padV = fontSize * 0.35

            var rect = CGRect(x: point.x - textSize.width / 2 - padH,
                              y: point.y - textSize.height / 2 - padV,
                              width: textSize.width + padH * 2,
                              height: textSize.height + padV * 2)
            rect.origin.x = min(max(rect.origin.x, 8),
                                image.size.width - rect.width - 8)
            rect.origin.y = min(max(rect.origin.y, 8),
                                image.size.height - rect.height - 8)

            let capsule = UIBezierPath(roundedRect: rect,
                                       cornerRadius: rect.height / 2)
            UIColor.black.withAlphaComponent(0.65).setFill()
            capsule.fill()
            (text as NSString).draw(
                at: CGPoint(x: rect.midX - textSize.width / 2,
                            y: rect.midY - textSize.height / 2),
                withAttributes: attrs)
        }
    }
}
