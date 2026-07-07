import Foundation

public struct SpeciesBar: Equatable, Sendable {
    public let name: String
    public let count: Int
    /// 相對最大種類數的比例(最大者 = 1.0),供長條寬度使用
    public let fraction: Double
}

public struct SizeBin: Equatable, Sendable {
    public let label: String
    public let count: Int
    /// 相對最大 bin 的比例(最大者 = 1.0),供柱高使用
    public let fraction: Double
}

/// 統計頁的彙總計算(種類長條、尺寸分布、同步狀態)。
public enum CatchStatistics {

    /// 尺寸分布區間(cm):下界含、上界不含;最後一區開放。
    public static let sizeBinEdges: [Double] = [0, 15, 25, 35, 50, 70]

    public static func speciesBars(from entries: [CatchEntry]) -> [SpeciesBar] {
        var counts: [String: Int] = [:]
        for e in entries { counts[e.species, default: 0] += 1 }
        guard let maxCount = counts.values.max() else { return [] }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { SpeciesBar(name: $0.key, count: $0.value,
                              fraction: Double($0.value) / Double(maxCount)) }
    }

    public static func sizeBins(from entries: [CatchEntry]) -> [SizeBin] {
        let edges = sizeBinEdges
        var counts = [Int](repeating: 0, count: edges.count)
        for e in entries {
            guard let len = e.lengthCM else { continue }
            // 由高往低找第一個 len >= 下界的區間
            if let idx = edges.lastIndex(where: { len >= $0 }) {
                counts[idx] += 1
            }
        }
        let maxCount = max(counts.max() ?? 0, 1)
        return counts.enumerated().map { idx, count in
            let lower = Int(edges[idx])
            let label = idx == edges.count - 1
                ? "\(lower)+"
                : "\(lower)-\(Int(edges[idx + 1]))"
            return SizeBin(label: label, count: count,
                           fraction: Double(count) / Double(maxCount))
        }
    }

    public static func unsyncedCount(of entries: [CatchEntry]) -> Int {
        entries.lazy.filter { !$0.isSynced }.count
    }
}
