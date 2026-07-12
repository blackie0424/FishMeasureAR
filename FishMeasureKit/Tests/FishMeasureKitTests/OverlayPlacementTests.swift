import XCTest
@testable import FishMeasureKit

/// 量魚板預設擺位:與魚線平行、0 刻度端(圖頂端)對齊 A 點(吻端)、
/// 沿法線偏移 gap 不遮魚;使用者仍可手動微調。
final class OverlayPlacementTests: XCTestCase {

    func testHorizontalFishPlacesBoardBelowZeroAlignedToA() {
        let placement = OverlayPlacement.boardPlacement(
            fishA: PlanePoint(x: 100, y: 100),
            fishB: PlanePoint(x: 500, y: 100),
            boardLengthPx: 600, gapPx: 50)!
        // 板中心 = A + 魚方向*板長/2 + 法線*gap
        XCTAssertEqual(placement.center.x, 400, accuracy: 1e-9)
        XCTAssertEqual(placement.center.y, 150, accuracy: 1e-9)
        // 水平魚(→):板轉 -90°,0 端(圖頂)指向 A
        XCTAssertEqual(placement.rotationDegrees, -90, accuracy: 1e-9)
    }

    func testVerticalFishKeepsBoardUprightBesideIt() {
        let placement = OverlayPlacement.boardPlacement(
            fishA: PlanePoint(x: 100, y: 100),
            fishB: PlanePoint(x: 100, y: 500),
            boardLengthPx: 600, gapPx: 50)!
        XCTAssertEqual(placement.center.x, 50, accuracy: 1e-9)
        XCTAssertEqual(placement.center.y, 400, accuracy: 1e-9)
        // 垂直魚(↓):板不旋轉(0 端已在上=A 側)
        XCTAssertEqual(placement.rotationDegrees, 0, accuracy: 1e-9)
    }

    func testDegenerateInputsReturnNil() {
        XCTAssertNil(OverlayPlacement.boardPlacement(
            fishA: PlanePoint(x: 5, y: 5), fishB: PlanePoint(x: 5, y: 5),
            boardLengthPx: 600, gapPx: 50))
        XCTAssertNil(OverlayPlacement.boardPlacement(
            fishA: PlanePoint(x: 0, y: 0), fishB: PlanePoint(x: 100, y: 0),
            boardLengthPx: 0, gapPx: 50))
    }
}

/// 拍攝物合成到數位量魚板:把照片中的魚(A→B)變換到板座標——
/// A 對齊 0 刻度、沿板軸向下、依 cm/px 等比縮放。
final class BoardCompositeTests: XCTestCase {

    func testHorizontalFishScalesAndRotatesToBoardAxis() {
        // 魚 30cm、照片上 A→B 300px、板 20px/cm
        // → 縮放 = 30*20/300 = 2;水平魚(→)轉 90° 對齊板軸(↓)
        let t = BoardComposite.transform(
            fishA: PlanePoint(x: 100, y: 200),
            fishB: PlanePoint(x: 400, y: 200),
            lengthCM: 30, boardPxPerCM: 20)!
        XCTAssertEqual(t.scale, 2.0, accuracy: 1e-9)
        XCTAssertEqual(t.rotationDegrees, 90, accuracy: 1e-9)
    }

    func testVerticalFishNeedsNoRotation() {
        let t = BoardComposite.transform(
            fishA: PlanePoint(x: 0, y: 0),
            fishB: PlanePoint(x: 0, y: 300),
            lengthCM: 30, boardPxPerCM: 20)!
        XCTAssertEqual(t.scale, 2.0, accuracy: 1e-9)
        XCTAssertEqual(t.rotationDegrees, 0, accuracy: 1e-9)
    }

    func testDegenerateInputsReturnNil() {
        XCTAssertNil(BoardComposite.transform(
            fishA: PlanePoint(x: 5, y: 5), fishB: PlanePoint(x: 5, y: 5),
            lengthCM: 30, boardPxPerCM: 20))
        XCTAssertNil(BoardComposite.transform(
            fishA: PlanePoint(x: 0, y: 0), fishB: PlanePoint(x: 100, y: 0),
            lengthCM: 0, boardPxPerCM: 20))
    }
}
