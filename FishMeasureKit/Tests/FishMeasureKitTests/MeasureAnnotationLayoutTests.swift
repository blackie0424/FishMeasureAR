import XCTest
@testable import FishMeasureKit

/// 長度標籤在照片上的擺放:線段中點沿法線偏移,優先放在線上方,並夾在影像範圍內。
final class MeasureAnnotationLayoutTests: XCTestCase {

    func testHorizontalLinePutsLabelAbove() {
        let pos = MeasureAnnotationLayout.labelPosition(
            p1: PlanePoint(x: 100, y: 500), p2: PlanePoint(x: 300, y: 500),
            offset: 40, width: 1000, height: 1000)
        XCTAssertEqual(pos.x, 200, accuracy: 1e-9, "x 在中點")
        XCTAssertEqual(pos.y, 460, accuracy: 1e-9, "在線上方(y 較小)")
    }

    func testVerticalLineOffsetsHorizontally() {
        let pos = MeasureAnnotationLayout.labelPosition(
            p1: PlanePoint(x: 500, y: 100), p2: PlanePoint(x: 500, y: 300),
            offset: 40, width: 1000, height: 1000)
        XCTAssertEqual(pos.y, 200, accuracy: 1e-9)
        XCTAssertEqual(abs(pos.x - 500), 40, accuracy: 1e-9, "沿法線水平偏移")
    }

    func testDegenerateLineFallsBackToPointAboveOffset() {
        let p = PlanePoint(x: 500, y: 500)
        let pos = MeasureAnnotationLayout.labelPosition(
            p1: p, p2: p, offset: 40, width: 1000, height: 1000)
        XCTAssertEqual(pos.x, 500, accuracy: 1e-9)
        XCTAssertEqual(pos.y, 460, accuracy: 1e-9, "退化線段:直接放點上方")
    }

    func testLabelIsClampedInsideBounds() {
        // 線貼近上緣,上方放不下 → 夾回邊界內(不小於 offset 邊距)
        let pos = MeasureAnnotationLayout.labelPosition(
            p1: PlanePoint(x: 100, y: 10), p2: PlanePoint(x: 300, y: 10),
            offset: 40, width: 1000, height: 1000)
        XCTAssertGreaterThanOrEqual(pos.y, 40)
        XCTAssertLessThanOrEqual(pos.y, 960)

        // 線貼近左緣的垂直線 → x 夾回
        let pos2 = MeasureAnnotationLayout.labelPosition(
            p1: PlanePoint(x: 5, y: 100), p2: PlanePoint(x: 5, y: 300),
            offset: 40, width: 1000, height: 1000)
        XCTAssertGreaterThanOrEqual(pos2.x, 40)
    }
}
