import XCTest
@testable import FishMeasureKit

final class CSVExporterTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func entry(species: String = "吳郭魚",
                       length: Double? = 31.25,
                       method: String? = "岸釣",
                       lat: Double? = 25.108, lon: Double? = 121.923,
                       place: String? = "龍洞漁港",
                       synced: Bool = false) -> CatchEntry {
        CatchEntry(species: species, lengthCM: length, method: method,
                   capturedAt: Date(timeIntervalSince1970: 1_783_500_000), // 2026-07-08 04:00:00 UTC
                   latitude: lat, longitude: lon, placeName: place, isSynced: synced)
    }

    func testHeaderAndRowCount() {
        let csv = CSVExporter.export([entry(), entry(species: "午仔")], timeZone: utc)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.first,
            "species,length_cm,method,captured_at,latitude,longitude,place,synced")
        XCTAssertEqual(lines.count, 3)
    }

    func testRowValues() {
        let csv = CSVExporter.export([entry()], timeZone: utc)
        let row = csv.split(separator: "\n").dropFirst().first!
        XCTAssertEqual(String(row),
            "吳郭魚,31.3,岸釣,2026-07-08 04:00:00,25.108,121.923,龍洞漁港,0",
            "長度輸出到 0.1cm;時間用指定時區;synced 用 0/1")
    }

    func testNilFieldsExportEmpty() {
        let csv = CSVExporter.export(
            [entry(length: nil, method: nil, lat: nil, lon: nil, place: nil)],
            timeZone: utc)
        let row = csv.split(separator: "\n").dropFirst().first!
        XCTAssertEqual(String(row), "吳郭魚,,,2026-07-08 04:00:00,,,,0")
    }

    func testFieldsWithCommaOrQuoteAreEscaped() {
        let csv = CSVExporter.export(
            [entry(species: #"石斑,"大隻""#, place: nil, synced: true)],
            timeZone: utc)
        let row = String(csv.split(separator: "\n").dropFirst().first!)
        XCTAssertTrue(row.hasPrefix(#""石斑,""大隻""","#), "逗號與引號需照 RFC4180 跳脫,實際: \(row)")
        XCTAssertTrue(row.hasSuffix(",1"))
    }

    func testFilenameUsesDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 7))!
        XCTAssertEqual(CSVExporter.filename(for: date, timeZone: utc), "catch_20260707.csv")
    }
}
