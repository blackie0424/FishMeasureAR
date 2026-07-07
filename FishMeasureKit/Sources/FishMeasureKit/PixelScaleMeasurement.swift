import Foundation

/// 2D 平面點(不依賴 CoreGraphics,Linux 可測)。
public struct PlanePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: PlanePoint) -> Double {
        let dx = x - other.x, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// 照片像素長度 ↔ 實際公分的換算(比例尺步驟與端點微調的核心數學)。
public enum PixelScaleMeasurement {

    /// 以已知尺寸比例尺換算魚長:fishPx / scalePx * scaleCM。
    /// 比例尺退化(兩端重合)或長度非正 → nil。
    public static func lengthCM(fishA: PlanePoint, fishB: PlanePoint,
                                scaleA: PlanePoint, scaleB: PlanePoint,
                                scaleLengthCM: Double) -> Double? {
        let scalePx = scaleA.distance(to: scaleB)
        guard scalePx > 0, scaleLengthCM > 0 else { return nil }
        return fishA.distance(to: fishB) / scalePx * scaleLengthCM
    }

    /// 由已知長度的線段推得 cm/px(AR 測得長度後,供手動微調端點時重新換算)。
    public static func cmPerPixel(lengthCM: Double,
                                  pointA: PlanePoint, pointB: PlanePoint) -> Double? {
        let px = pointA.distance(to: pointB)
        guard px > 0, lengthCM > 0 else { return nil }
        return lengthCM / px
    }

    public static func length(from a: PlanePoint, to b: PlanePoint,
                              cmPerPixel: Double) -> Double {
        a.distance(to: b) * cmPerPixel
    }
}
