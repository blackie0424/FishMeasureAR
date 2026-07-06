import Foundation

/// 測量值穩定器:保留最近 N 個讀值,輸出中位數;
/// 標準差低於門檻時判定為「穩定」(UI 顯示綠色、允許拍攝)。
struct MeasurementSmoother {
    private var window: [Double] = []
    private let capacity = 15
    private let stableStdDevCM = 0.4

    mutating func push(_ lengthMeters: Double) {
        window.append(lengthMeters)
        if window.count > capacity { window.removeFirst() }
    }

    mutating func reset() { window.removeAll() }

    /// 中位數(公尺)
    var median: Double? {
        guard !window.isEmpty else { return nil }
        let sorted = window.sorted()
        return sorted[sorted.count / 2]
    }

    /// 是否穩定:視窗滿且標準差 < 0.4cm
    var isStable: Bool {
        guard window.count == capacity, let m = mean else { return false }
        let variance = window.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(window.count)
        return variance.squareRoot() * 100 < stableStdDevCM
    }

    private var mean: Double? {
        guard !window.isEmpty else { return nil }
        return window.reduce(0, +) / Double(window.count)
    }
}
