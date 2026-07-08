import Foundation

/// 拍攝畫面主按鈕的動作(唯一一顆,依情境切換)。
public enum CaptureMainAction: Equatable, Sendable {
    case addPoint   // 「＋」:準星處設量測點
    case shutter    // 快門:拍照
}

/// 主按鈕情境邏輯:單拍未完成量測 = 設點,完成 = 快門;連拍一律快門。
public enum CaptureControls {

    public static func mainAction(mode: CaptureMode,
                                  isComplete: Bool) -> CaptureMainAction {
        if mode == .burst { return .shutter }
        return isComplete ? .shutter : .addPoint
    }

    /// 設點需要準星命中表面;快門不受限。
    public static func isEnabled(_ action: CaptureMainAction,
                                 reticleHasSurface: Bool) -> Bool {
        action == .shutter || reticleHasSurface
    }
}
