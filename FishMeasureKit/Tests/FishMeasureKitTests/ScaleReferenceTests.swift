import XCTest
@testable import FishMeasureKit

final class ScaleReferenceTests: XCTestCase {

    func testCatalogStartsWithNoneOption() {
        let first = ScaleReference.catalog.first
        XCTAssertEqual(first?.id, "none")
        XCTAssertNil(first?.lengthCM, "「無」代表不換算長度")
    }

    func testAllRealReferencesHavePositiveLength() {
        for ref in ScaleReference.catalog.dropFirst() {
            XCTAssertNotNil(ref.lengthCM, "\(ref.name) 缺長度")
            XCTAssertGreaterThan(ref.lengthCM ?? 0, 0, "\(ref.name) 長度須為正")
        }
    }

    func testIDsAreUnique() {
        let ids = ScaleReference.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testOverlayImageAvailability() {
        // 打火機/藍白拖有去背疊圖素材;其餘尚無
        func imageName(_ id: String) -> String? {
            ScaleReference.catalog.first { $0.id == id }?.imageName
        }
        XCTAssertEqual(imageName("lighter"), "ref-lighter")
        XCTAssertEqual(imageName("slipper"), "ref-slipper")
        XCTAssertNil(imageName("none"))
        XCTAssertNil(imageName("ruler30"))
    }

    func testCatalogMatchesARReferenceObjectSizes() {
        // 與 AR 參照物(ReferenceObjects.swift)同一套真實尺寸,單一事實來源
        func length(_ id: String) -> Double? {
            ScaleReference.catalog.first { $0.id == id }?.lengthCM
        }
        XCTAssertEqual(length("slipper"), 26.0)
        XCTAssertEqual(length("lighter"), 8.1)
        XCTAssertEqual(length("ruler30"), 30.0)
    }
}
