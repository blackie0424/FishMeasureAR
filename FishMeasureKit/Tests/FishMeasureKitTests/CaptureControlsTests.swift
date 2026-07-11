import XCTest
@testable import FishMeasureKit

/// 拍攝畫面主按鈕:點位改為「直接點照片任意位置」設定後,
/// 主按鈕只剩快門一種角色——單拍需完成量測,連拍隨時可拍。
final class CaptureControlsTests: XCTestCase {

    func testSingleModeShutterRequiresCompleteMeasurement() {
        XCTAssertFalse(CaptureControls.shutterEnabled(mode: .single, isComplete: false))
        XCTAssertTrue(CaptureControls.shutterEnabled(mode: .single, isComplete: true))
    }

    func testBurstModeShutterAlwaysEnabled() {
        XCTAssertTrue(CaptureControls.shutterEnabled(mode: .burst, isComplete: false))
        XCTAssertTrue(CaptureControls.shutterEnabled(mode: .burst, isComplete: true))
    }
}
