import XCTest
@testable import FishMeasureKit

/// 依 UI 原型(漁獲測量原型.html)定義的五畫面工作流:
/// 拍照 → 量魚 → (比例尺) → 表單 → 統計,含單拍/連拍模式與魚種必填驗證。
final class MeasureFlowTests: XCTestCase {

    // MARK: 初始狀態

    func testInitialState() {
        let flow = MeasureFlow()
        XCTAssertEqual(flow.screen, .capture)
        XCTAssertEqual(flow.mode, .single)
        XCTAssertEqual(flow.pendingShots, 0)
        XCTAssertFalse(flow.isMeasuringPending)
        XCTAssertNil(flow.selectedSpecies)
        XCTAssertNil(flow.selectedMethod)
        XCTAssertFalse(flow.speciesValidationFailed)
    }

    // MARK: 拍照:單拍/連拍

    func testShutterInSingleModeGoesToAdjustFish() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        XCTAssertEqual(flow.screen, .adjustFish)
        XCTAssertEqual(flow.pendingShots, 0)
    }

    func testShutterWithCompletedMeasurementGoesToOverlayEdit() {
        // 測距儀式兩點已設定 → 先進比例尺編輯,結束才到表單
        var flow = MeasureFlow()
        flow.shutterPressed(measurementReady: true)
        XCTAssertEqual(flow.screen, .overlayEdit)
    }

    func testOverlayEditAdvancesToForm() {
        var flow = MeasureFlow()
        flow.shutterPressed(measurementReady: true)
        flow.advanceFromOverlayEdit()
        XCTAssertEqual(flow.screen, .form)
    }

    func testOverlayEditBackForMetricPathReturnsToCapture() {
        var flow = MeasureFlow()
        flow.shutterPressed(measurementReady: true)
        flow.backFromOverlayEdit(hasMetricLength: true)
        XCTAssertEqual(flow.screen, .capture)
    }

    func testOverlayEditBackForManualPathReturnsToScale() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: false)
        flow.advanceFromScale()
        flow.backFromOverlayEdit(hasMetricLength: false)
        XCTAssertEqual(flow.screen, .scale)
    }

    func testBurstShutterIgnoresMeasurementReady() {
        var flow = MeasureFlow()
        flow.setMode(.burst)
        flow.shutterPressed(measurementReady: true)
        XCTAssertEqual(flow.screen, .capture)
        XCTAssertEqual(flow.pendingShots, 1)
    }

    func testShutterInBurstModeAccumulatesPendingAndStaysOnCapture() {
        var flow = MeasureFlow()
        flow.setMode(.burst)
        flow.shutterPressed()
        flow.shutterPressed()
        flow.shutterPressed()
        XCTAssertEqual(flow.screen, .capture)
        XCTAssertEqual(flow.pendingShots, 3)
    }

    func testEndBurstReturnsToSingleModeAndShowsStats() {
        var flow = MeasureFlow()
        flow.setMode(.burst)
        flow.shutterPressed()
        flow.endBurst()
        XCTAssertEqual(flow.mode, .single)
        XCTAssertEqual(flow.screen, .stats)
        XCTAssertEqual(flow.pendingShots, 1, "結束連拍不清空待量測佇列")
    }

    // MARK: 量魚 → 比例尺/表單

    func testAdvanceFromAdjustFishNeedsScaleStepWhenNoMetricLength() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: false)
        XCTAssertEqual(flow.screen, .scale)
    }

    func testAdvanceFromAdjustFishSkipsScaleStepWhenMetricLengthKnown() {
        // AR(LiDAR)已給出公制長度時,不需比例尺步驟
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: true)
        XCTAssertEqual(flow.screen, .overlayEdit)
    }

    func testScaleStepAdvancesToForm() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: false)
        flow.advanceFromScale()
        XCTAssertEqual(flow.screen, .overlayEdit)
    }

    func testBackNavigation() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: false)
        flow.backToAdjustFish()
        XCTAssertEqual(flow.screen, .adjustFish)
        flow.backToCapture()
        XCTAssertEqual(flow.screen, .capture)
    }

    // MARK: 表單:魚種必填

    func testSaveWithoutSpeciesFailsValidation() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: true)
        flow.advanceFromOverlayEdit()
        let saved = flow.save(to: .captureNext)
        XCTAssertFalse(saved)
        XCTAssertTrue(flow.speciesValidationFailed)
        XCTAssertEqual(flow.screen, .form, "驗證失敗須停在表單")
    }

    func testSelectingSpeciesClearsValidationFlag() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: true)
        flow.advanceFromOverlayEdit()
        _ = flow.save(to: .captureNext)
        flow.selectSpecies("吳郭魚")
        XCTAssertFalse(flow.speciesValidationFailed)
        XCTAssertEqual(flow.selectedSpecies, "吳郭魚")
    }

    func testSaveWithSpeciesResetsSelectionAndNavigates() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: true)
        flow.advanceFromOverlayEdit()
        flow.selectSpecies("白帶魚")
        flow.selectMethod("船釣")
        let saved = flow.save(to: .captureNext)
        XCTAssertTrue(saved)
        XCTAssertEqual(flow.screen, .capture)
        XCTAssertNil(flow.selectedSpecies, "儲存後清空,準備下一尾")
        XCTAssertNil(flow.selectedMethod)
    }

    func testSaveToStats() {
        var flow = MeasureFlow()
        flow.shutterPressed()
        flow.advanceFromAdjustFish(hasMetricLength: true)
        flow.advanceFromOverlayEdit()
        flow.selectSpecies("午仔")
        XCTAssertTrue(flow.save(to: .stats))
        XCTAssertEqual(flow.screen, .stats)
    }

    // MARK: 連拍佇列的批次量測

    func testStartMeasuringPendingFromStats() {
        var flow = MeasureFlow()
        flow.setMode(.burst)
        flow.shutterPressed()
        flow.shutterPressed()
        flow.endBurst()

        flow.startMeasuringPending()
        XCTAssertEqual(flow.screen, .adjustFish)
        XCTAssertTrue(flow.isMeasuringPending)
    }

    func testStartMeasuringPendingIsNoOpWithEmptyQueue() {
        var flow = MeasureFlow()
        flow.goToStats()
        flow.startMeasuringPending()
        XCTAssertEqual(flow.screen, .stats)
        XCTAssertFalse(flow.isMeasuringPending)
    }

    func testSavingPendingShotDecrementsQueue() {
        var flow = MeasureFlow()
        flow.setMode(.burst)
        flow.shutterPressed()
        flow.shutterPressed()
        flow.endBurst()
        flow.startMeasuringPending()
        flow.advanceFromAdjustFish(hasMetricLength: false)
        flow.advanceFromScale()
        flow.advanceFromOverlayEdit()
        flow.selectSpecies("花身仔")
        XCTAssertTrue(flow.save(to: .stats))
        XCTAssertEqual(flow.pendingShots, 1)
        XCTAssertFalse(flow.isMeasuringPending, "儲存後重置批次量測旗標")
    }

    func testSavingNormalShotDoesNotTouchPendingQueue() {
        var flow = MeasureFlow()
        flow.setMode(.burst)
        flow.shutterPressed()   // pending = 1
        flow.setMode(.single)
        flow.shutterPressed()   // 一般單拍
        flow.advanceFromAdjustFish(hasMetricLength: true)
        flow.advanceFromOverlayEdit()
        flow.selectSpecies("黑鯛")
        XCTAssertTrue(flow.save(to: .stats))
        XCTAssertEqual(flow.pendingShots, 1)
    }
}
