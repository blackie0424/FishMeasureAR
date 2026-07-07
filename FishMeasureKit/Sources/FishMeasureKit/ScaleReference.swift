import Foundation

/// 比例尺參照物:真實尺寸(公分)的單一事實來源。
/// AR 參照物(ReferenceObjects.swift)與照片比例尺步驟共用此目錄。
public struct ScaleReference: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// 沿量測方向的實際長度(cm);nil 代表「無」(不換算)
    public let lengthCM: Double?

    public init(id: String, name: String, lengthCM: Double?) {
        self.id = id
        self.name = name
        self.lengthCM = lengthCM
    }

    public static let catalog: [ScaleReference] = [
        ScaleReference(id: "none", name: "無", lengthCM: nil),
        ScaleReference(id: "lighter", name: "打火機", lengthCM: 8.1),      // BIC 大
        ScaleReference(id: "slipper", name: "藍白拖", lengthCM: 26.0),
        ScaleReference(id: "can330", name: "330ml 鋁罐", lengthCM: 11.5),  // 罐高
        ScaleReference(id: "easycard", name: "悠遊卡", lengthCM: 8.56),    // ISO ID-1 長邊
        ScaleReference(id: "bottle600", name: "600ml 寶特瓶", lengthCM: 20.5),
        ScaleReference(id: "ruler30", name: "30cm 直尺", lengthCM: 30.0),
    ]
}
