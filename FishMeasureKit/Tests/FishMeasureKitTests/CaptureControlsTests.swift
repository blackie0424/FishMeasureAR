import XCTest
@testable import FishMeasureKit

/// 拍攝畫面唯一主按鈕的情境邏輯:
/// 單拍模式下未完成量測 = 「＋」設點,兩點齊備 = 快門;連拍模式一律快門。
final class CaptureControlsTests: XCTestCase {

    func testSingleModeBeforeCompleteIsAddPoint() {
        XCTAssertEqual(CaptureControls.mainAction(mode: .single, isComplete: false),
                       .addPoint)
    }

    func testSingleModeAfterCompleteIsShutter() {
        XCTAssertEqual(CaptureControls.mainAction(mode: .single, isComplete: true),
                       .shutter)
    }

    func testBurstModeIsAlwaysShutter() {
        XCTAssertEqual(CaptureControls.mainAction(mode: .burst, isComplete: false),
                       .shutter)
        XCTAssertEqual(CaptureControls.mainAction(mode: .burst, isComplete: true),
                       .shutter)
    }

    func testAddPointRequiresSurface() {
        XCTAssertFalse(CaptureControls.isEnabled(.addPoint, reticleHasSurface: false))
        XCTAssertTrue(CaptureControls.isEnabled(.addPoint, reticleHasSurface: true))
    }

    func testShutterDoesNotRequireSurface() {
        XCTAssertTrue(CaptureControls.isEnabled(.shutter, reticleHasSurface: false))
    }
}
