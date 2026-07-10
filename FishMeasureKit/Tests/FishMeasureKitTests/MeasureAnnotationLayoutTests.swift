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

    // MARK: 氣泡旋轉(橫向拍攝時調整數字方向,90° 循環)

    func testRotationCyclesQuarterTurns() {
        XCTAssertEqual(MeasureAnnotationLayout.nextRotation(0), 90)
        XCTAssertEqual(MeasureAnnotationLayout.nextRotation(90), 180)
        XCTAssertEqual(MeasureAnnotationLayout.nextRotation(180), 270)
        XCTAssertEqual(MeasureAnnotationLayout.nextRotation(270), 0, "轉滿一圈回正")
    }

    func testRotationNormalizesArbitraryInput() {
        XCTAssertEqual(MeasureAnnotationLayout.nextRotation(45), 90, "非 90 倍數就近取整到下一段")
        XCTAssertEqual(MeasureAnnotationLayout.nextRotation(-90), 0)
    }

    // MARK: 使用者拖曳氣泡:線中點 + 偏移 + 邊界夾制(螢幕與照片共用同一算式)

    func testDisplayPositionZeroOffsetSitsOnMidpoint() {
        let pos = MeasureAnnotationLayout.displayPosition(
            midpoint: PlanePoint(x: 400, y: 300),
            offsetX: 0, offsetY: 0,
            width: 800, height: 600, margin: 50)
        XCTAssertEqual(pos, PlanePoint(x: 400, y: 300))
    }

    func testDisplayPositionAppliesUserOffset() {
        let pos = MeasureAnnotationLayout.displayPosition(
            midpoint: PlanePoint(x: 400, y: 300),
            offsetX: -120, offsetY: 80,
            width: 800, height: 600, margin: 50)
        XCTAssertEqual(pos, PlanePoint(x: 280, y: 380))
    }

    func testDisplayPositionClampsToMargin() {
        // 拖出邊界 → 夾回 margin 內
        let pos = MeasureAnnotationLayout.displayPosition(
            midpoint: PlanePoint(x: 400, y: 300),
            offsetX: 1000, offsetY: -1000,
            width: 800, height: 600, margin: 50)
        XCTAssertEqual(pos, PlanePoint(x: 750, y: 50))
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
