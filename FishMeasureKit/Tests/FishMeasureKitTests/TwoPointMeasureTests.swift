import XCTest
@testable import FishMeasureKit

/// 仿 iOS 測距儀的兩點量測:準星設定 A、B 兩點(世界座標,公尺),
/// 兩點齊備即可得長度並拍攝。
final class TwoPointMeasureTests: XCTestCase {

    func testInitialStateIsEmpty() {
        let m = TwoPointMeasure()
        XCTAssertEqual(m.points.count, 0)
        XCTAssertTrue(m.canAddPoint)
        XCTAssertFalse(m.isComplete)
        XCTAssertNil(m.lengthMeters)
        XCTAssertNil(m.lengthCM)
    }

    func testAddFirstPoint() {
        var m = TwoPointMeasure()
        XCTAssertTrue(m.addPoint(WorldPoint(x: 0, y: 0, z: 0)))
        XCTAssertEqual(m.points.count, 1)
        XCTAssertTrue(m.canAddPoint)
        XCTAssertFalse(m.isComplete)
        XCTAssertNil(m.lengthMeters, "單點沒有長度")
    }

    func testAddSecondPointCompletesMeasure() {
        var m = TwoPointMeasure()
        m.addPoint(WorldPoint(x: 0, y: 0, z: 0))
        XCTAssertTrue(m.addPoint(WorldPoint(x: 0.3, y: 0, z: 0)))
        XCTAssertTrue(m.isComplete)
        XCTAssertFalse(m.canAddPoint)
        XCTAssertEqual(m.lengthMeters!, 0.3, accuracy: 1e-9)
        XCTAssertEqual(m.lengthCM!, 30.0, accuracy: 1e-9)
    }

    func testThirdPointIsRejected() {
        var m = TwoPointMeasure()
        m.addPoint(WorldPoint(x: 0, y: 0, z: 0))
        m.addPoint(WorldPoint(x: 1, y: 0, z: 0))
        XCTAssertFalse(m.addPoint(WorldPoint(x: 2, y: 0, z: 0)))
        XCTAssertEqual(m.points.count, 2)
        XCTAssertEqual(m.lengthMeters!, 1.0, accuracy: 1e-9, "長度不受第三點影響")
    }

    func testLengthUses3DDistance() {
        // 3-4-12 → 13(3D 畢氏)
        var m = TwoPointMeasure()
        m.addPoint(WorldPoint(x: 0, y: 0, z: 0))
        m.addPoint(WorldPoint(x: 0.03, y: 0.04, z: 0.12))
        XCTAssertEqual(m.lengthMeters!, 0.13, accuracy: 1e-9)
    }

    func testUndoRemovesLastPoint() {
        var m = TwoPointMeasure()
        m.addPoint(WorldPoint(x: 0, y: 0, z: 0))
        m.addPoint(WorldPoint(x: 1, y: 0, z: 0))
        m.undoLastPoint()
        XCTAssertEqual(m.points.count, 1)
        XCTAssertEqual(m.points.first, WorldPoint(x: 0, y: 0, z: 0), "移除的是後設的點")
        XCTAssertNil(m.lengthMeters)
        m.undoLastPoint()
        XCTAssertTrue(m.points.isEmpty)
        m.undoLastPoint()   // 空佇列不可爆
        XCTAssertTrue(m.points.isEmpty)
    }

    func testResetClearsEverything() {
        var m = TwoPointMeasure()
        m.addPoint(WorldPoint(x: 0, y: 0, z: 0))
        m.addPoint(WorldPoint(x: 1, y: 0, z: 0))
        m.reset()
        XCTAssertTrue(m.points.isEmpty)
        XCTAssertTrue(m.canAddPoint)
        XCTAssertNil(m.lengthMeters)
    }

    func testWorldPointDistance() {
        let a = WorldPoint(x: 1, y: 2, z: 3)
        let b = WorldPoint(x: 1, y: 2, z: 3)
        XCTAssertEqual(a.distance(to: b), 0, accuracy: 1e-12)
    }
}
