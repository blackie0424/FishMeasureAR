import Foundation

/// 3D 世界座標點(公尺)。不依賴 simd,Linux 可測。
public struct WorldPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func distance(to other: WorldPoint) -> Double {
        let dx = x - other.x, dy = y - other.y, dz = z - other.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

/// 仿 iOS 測距儀的兩點量測狀態:準星設 A、B 兩點,齊備即得長度。
public struct TwoPointMeasure: Equatable, Sendable {
    public private(set) var points: [WorldPoint] = []

    public init() {}

    public var canAddPoint: Bool { points.count < 2 }
    public var isComplete: Bool { points.count == 2 }

    /// 新增量測點。已有兩點時拒絕(需先 undo/reset)。
    @discardableResult
    public mutating func addPoint(_ point: WorldPoint) -> Bool {
        guard canAddPoint else { return false }
        points.append(point)
        return true
    }

    public mutating func undoLastPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
    }

    public mutating func reset() {
        points.removeAll()
    }

    public var lengthMeters: Double? {
        guard isComplete else { return nil }
        return points[0].distance(to: points[1])
    }

    public var lengthCM: Double? {
        lengthMeters.map { $0 * 100 }
    }
}
