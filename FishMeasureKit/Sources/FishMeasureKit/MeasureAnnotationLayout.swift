import Foundation

/// 長度標籤在照片上的擺放:線段中點沿法線偏移,
/// 優先放在線「上方」(y 較小側),再夾進影像邊界。
public enum MeasureAnnotationLayout {

    public static func labelPosition(p1: PlanePoint, p2: PlanePoint,
                                     offset: Double,
                                     width: Double, height: Double) -> PlanePoint {
        let mid = PlanePoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let len = (dx * dx + dy * dy).squareRoot()

        var candidate: PlanePoint
        if len > 0 {
            // 單位法線,取指向畫面上方(y 較小)的那一側
            var nx = -dy / len, ny = dx / len
            if ny > 0 { nx = -nx; ny = -ny }
            candidate = PlanePoint(x: mid.x + nx * offset, y: mid.y + ny * offset)
        } else {
            candidate = PlanePoint(x: mid.x, y: mid.y - offset)
        }

        candidate.x = min(max(candidate.x, offset), width - offset)
        candidate.y = min(max(candidate.y, offset), height - offset)
        return candidate
    }

    /// 氣泡旋轉 90° 循環(垂直俯拍時重力無法判斷橫直向,由使用者手動切換;
    /// 任意輸入先正規化並向下取整到 90 的倍數)。
    public static func nextRotation(_ degrees: Int) -> Int {
        let normalized = ((degrees % 360) + 360) % 360
        let quarter = normalized / 90
        return ((quarter + 1) * 90) % 360
    }

    /// 數字氣泡顯示位置:線中點 + 使用者拖曳偏移,夾在邊界內。
    /// 螢幕顯示與照片合成共用同一算式,保證所見即所得。
    public static func displayPosition(midpoint: PlanePoint,
                                       offsetX: Double, offsetY: Double,
                                       width: Double, height: Double,
                                       margin: Double) -> PlanePoint {
        PlanePoint(
            x: min(max(midpoint.x + offsetX, margin), width - margin),
            y: min(max(midpoint.y + offsetY, margin), height - margin))
    }
}
