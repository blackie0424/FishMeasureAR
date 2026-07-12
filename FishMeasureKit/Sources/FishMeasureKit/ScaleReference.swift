import Foundation

/// 比例尺參照物:真實尺寸(公分)的單一事實來源。
/// AR 參照物(ReferenceObjects.swift)與照片比例尺步驟共用此目錄。
public struct ScaleReference: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// 沿量測方向的實際長度(cm);nil 代表「無」(不換算)
    public let lengthCM: Double?
    /// 照片疊圖素材(asset catalog 圖名);nil = 無疊圖
    public let imageName: String?

    public init(id: String, name: String, lengthCM: Double?,
                imageName: String? = nil) {
        self.id = id
        self.name = name
        self.lengthCM = lengthCM
        self.imageName = imageName
    }

    public static let catalog: [ScaleReference] = [
        ScaleReference(id: "none", name: "無", lengthCM: nil),
        // BIC Maxi J26 實高 81mm
        ScaleReference(id: "lighter", name: "打火機", lengthCM: 8.1,
                       imageName: "ref-lighter"),
        // 藍白拖 10 號 = 26cm(11 號 27、12 號 28;依實物調整此值)
        ScaleReference(id: "slipper", name: "藍白拖", lengthCM: 26.0,
                       imageName: "ref-slipper"),
        ScaleReference(id: "can330", name: "330ml 鋁罐", lengthCM: 11.5),  // 罐高
        ScaleReference(id: "easycard", name: "悠遊卡", lengthCM: 8.56),    // ISO ID-1 長邊
        ScaleReference(id: "bottle600", name: "600ml 寶特瓶", lengthCM: 20.5),
        ScaleReference(id: "ruler30", name: "30cm 直尺", lengthCM: 30.0),
    ]

    /// 有疊圖素材的參照物(照片後製擺放用)
    public static var overlayCatalog: [ScaleReference] {
        catalog.filter { $0.imageName != nil }
    }
}

/// 照片組的固定順序與替換規則:0 原圖、1 測量版、2 比例物版。
public enum PhotoSetLayout {
    /// 替換(或補上)比例物版照片 ID;空組不動(舊資料防呆)。
    public static func replacingReferencePhoto(in ids: [String],
                                               with newID: String) -> [String] {
        guard !ids.isEmpty else { return ids }
        var result = ids
        if result.count >= 3 {
            result[2] = newID
        } else {
            result.append(newID)
        }
        return result
    }
}
