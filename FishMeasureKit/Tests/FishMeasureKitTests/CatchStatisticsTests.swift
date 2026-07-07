import XCTest
@testable import FishMeasureKit

final class CatchStatisticsTests: XCTestCase {

    private func entry(_ species: String, _ length: Double?,
                       method: String? = nil, synced: Bool = true) -> CatchEntry {
        CatchEntry(species: species, lengthCM: length, method: method,
                   capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                   latitude: nil, longitude: nil, placeName: nil, isSynced: synced)
    }

    // MARK: 種類長條

    func testSpeciesBarsSortedByCountDescending() {
        let bars = CatchStatistics.speciesBars(from: [
            entry("吳郭魚", 31.2), entry("午仔", 22.1), entry("吳郭魚", 28.9),
        ])
        XCTAssertEqual(bars.map(\.name), ["吳郭魚", "午仔"])
        XCTAssertEqual(bars.map(\.count), [2, 1])
        XCTAssertEqual(bars[0].fraction, 1.0, accuracy: 1e-9, "最大值撐滿")
        XCTAssertEqual(bars[1].fraction, 0.5, accuracy: 1e-9)
    }

    func testSpeciesBarsEmptyInput() {
        XCTAssertTrue(CatchStatistics.speciesBars(from: []).isEmpty)
    }

    // MARK: 尺寸分布

    func testSizeBinsBoundariesAreLowerInclusiveUpperExclusive() {
        // 15.0 落在 15-25,不落在 0-15
        let bins = CatchStatistics.sizeBins(from: [
            entry("a", 14.9), entry("b", 15.0), entry("c", 24.9),
        ])
        XCTAssertEqual(bins.map(\.label), ["0-15", "15-25", "25-35", "35-50", "50-70", "70+"])
        XCTAssertEqual(bins[0].count, 1)
        XCTAssertEqual(bins[1].count, 2)
    }

    func testSizeBinsTopBinIsOpenEnded() {
        let bins = CatchStatistics.sizeBins(from: [entry("白帶魚", 88.4), entry("旗魚", 250)])
        XCTAssertEqual(bins.last?.count, 2)
    }

    func testSizeBinsIgnoreEntriesWithoutLength() {
        let bins = CatchStatistics.sizeBins(from: [entry("未量", nil), entry("a", 30)])
        XCTAssertEqual(bins.reduce(0) { $0 + $1.count }, 1)
    }

    func testSizeBinFractionsRelativeToLargestBin() {
        let bins = CatchStatistics.sizeBins(from: [
            entry("a", 10), entry("b", 12), entry("c", 30),
        ])
        XCTAssertEqual(bins[0].fraction, 1.0, accuracy: 1e-9)
        XCTAssertEqual(bins[2].fraction, 0.5, accuracy: 1e-9)
    }

    // MARK: 同步狀態

    func testUnsyncedCount() {
        let entries = [entry("a", 1, synced: true),
                       entry("b", 2, synced: false),
                       entry("c", 3, synced: false)]
        XCTAssertEqual(CatchStatistics.unsyncedCount(of: entries), 2)
    }
}
