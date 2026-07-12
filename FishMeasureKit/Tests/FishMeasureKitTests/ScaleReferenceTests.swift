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
        XCTAssertEqual(imageName("hand-board"), "ref-hand-board")
        XCTAssertNil(imageName("none"))
        XCTAssertNil(imageName("ruler30"))
    }

    func testHandBoardEntry() {
        // 全板 63cm(0→60 刻度 1323px+紅帶 66px,由實拍板量得);
        // 0 刻度於圖頂端,預設對齊拍攝物
        let hand = ScaleReference.catalog.first { $0.id == "hand-board" }
        XCTAssertEqual(hand?.name, "手")
        XCTAssertEqual(hand?.lengthCM ?? 0, 63.0, accuracy: 1e-9)
        XCTAssertTrue(hand?.alignsZeroToSubject ?? false)
        // 其他物件不做零點對齊
        let lighter = ScaleReference.catalog.first { $0.id == "lighter" }
        XCTAssertFalse(lighter?.alignsZeroToSubject ?? true)
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

/// 照片組固定順序(0 原圖/1 測量版/2 比例物版)的替換規則
final class PhotoSetLayoutTests: XCTestCase {

    func testReplacesExistingReferencePhoto() {
        XCTAssertEqual(PhotoSetLayout.replacingReferencePhoto(
            in: ["o", "m", "r"], with: "new"), ["o", "m", "new"])
    }

    func testAppendsWhenNoReferencePhotoYet() {
        XCTAssertEqual(PhotoSetLayout.replacingReferencePhoto(
            in: ["o", "m"], with: "new"), ["o", "m", "new"])
    }

    func testSingleLegacyPhotoAppends() {
        XCTAssertEqual(PhotoSetLayout.replacingReferencePhoto(
            in: ["only"], with: "new"), ["only", "new"])
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(PhotoSetLayout.replacingReferencePhoto(
            in: [], with: "new"), [])
    }
}
