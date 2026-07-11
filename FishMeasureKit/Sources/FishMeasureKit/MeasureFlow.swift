import Foundation

/// 工作流畫面:拍照/量魚/比例尺(換算)/比例尺編輯(疊圖擺放)/表單/統計。
public enum MeasureScreenState: Equatable, Sendable {
    case capture, adjustFish, scale, overlayEdit, form, stats
}

/// 拍攝模式:單拍立即量測;連拍先累積、稍後批次量測。
public enum CaptureMode: Equatable, Sendable {
    case single, burst
}

/// 五畫面工作流狀態機。純值型別,不含 UI 與 I/O,可完整單元測試。
public struct MeasureFlow: Equatable, Sendable {

    public private(set) var screen: MeasureScreenState = .capture
    public private(set) var mode: CaptureMode = .single
    public private(set) var pendingShots: Int = 0
    /// 目前的量測是否來自連拍佇列(儲存時要遞減 pendingShots)
    public private(set) var isMeasuringPending: Bool = false
    public private(set) var selectedSpecies: String? = nil
    public private(set) var selectedMethod: String? = nil
    /// 未選魚種就儲存 → true(UI 顯示「請先選擇魚種」)
    public private(set) var speciesValidationFailed: Bool = false

    public init() {}

    // MARK: 拍照

    public mutating func setMode(_ newMode: CaptureMode) {
        mode = newMode
    }

    /// - Parameter measurementReady: 快門當下量測已完成(測距儀式兩點已設定,
    ///   照片已合成線段與長度)→ 單拍先進比例尺編輯;否則進量魚畫面手動補量。
    ///   連拍一律只入佇列。
    public mutating func shutterPressed(measurementReady: Bool = false) {
        switch mode {
        case .single:
            isMeasuringPending = false
            screen = measurementReady ? .overlayEdit : .adjustFish
        case .burst:
            pendingShots += 1
        }
    }

    public mutating func endBurst() {
        mode = .single
        screen = .stats
    }

    // MARK: 導覽

    public mutating func goToStats() { screen = .stats }
    public mutating func backToCapture() { screen = .capture }
    public mutating func backToAdjustFish() { screen = .adjustFish }

    /// 量魚完成:已有公制長度可跳過比例尺換算,直接進疊圖編輯。
    public mutating func advanceFromAdjustFish(hasMetricLength: Bool) {
        screen = hasMetricLength ? .overlayEdit : .scale
    }

    public mutating func advanceFromScale() {
        screen = .overlayEdit
    }

    /// 比例尺編輯(疊圖擺放)結束 → 資料填寫。
    public mutating func advanceFromOverlayEdit() {
        screen = .form
    }

    /// 比例尺編輯往回:測距儀路徑回拍照(重拍),手動路徑回比例尺換算。
    public mutating func backFromOverlayEdit(hasMetricLength: Bool) {
        screen = hasMetricLength ? .capture : .scale
    }

    /// 從統計頁開始批次量測連拍佇列。
    public mutating func startMeasuringPending() {
        guard pendingShots > 0 else { return }
        isMeasuringPending = true
        screen = .adjustFish
    }

    // MARK: 表單

    public mutating func selectSpecies(_ species: String) {
        selectedSpecies = species
        speciesValidationFailed = false
    }

    public mutating func selectMethod(_ method: String) {
        selectedMethod = method
    }

    public enum SaveDestination: Equatable, Sendable {
        case captureNext   // 儲存＋再拍一尾
        case stats         // 儲存(離線)
    }

    /// 儲存表單。魚種必填:未選則回傳 false 並標記驗證失敗。
    /// 成功時清空選擇、處理連拍佇列並導向目的畫面。
    @discardableResult
    public mutating func save(to destination: SaveDestination) -> Bool {
        guard selectedSpecies != nil else {
            speciesValidationFailed = true
            return false
        }
        if isMeasuringPending {
            pendingShots = max(0, pendingShots - 1)
        }
        selectedSpecies = nil
        selectedMethod = nil
        speciesValidationFailed = false
        isMeasuringPending = false
        screen = destination == .captureNext ? .capture : .stats
        return true
    }
}
