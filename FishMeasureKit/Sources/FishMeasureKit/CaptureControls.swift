import Foundation

/// 拍攝畫面主按鈕邏輯。
/// 點位改為「直接點照片任意位置」設定(構圖先行,手機不必移動),
/// 主按鈕只剩快門:單拍需完成量測,連拍隨時可拍(入佇列稍後補量)。
public enum CaptureControls {

    public static func shutterEnabled(mode: CaptureMode,
                                      isComplete: Bool) -> Bool {
        mode == .burst || isComplete
    }
}
