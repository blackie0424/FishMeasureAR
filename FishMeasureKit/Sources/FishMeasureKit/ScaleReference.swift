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
    /// 量魚板類:預設擺位將 0 刻度端(圖頂端)對齊拍攝物 A 點
    public let alignsZeroToSubject: Bool

    public init(id: String, name: String, lengthCM: Double?,
                imageName: String? = nil,
                alignsZeroToSubject: Bool = false) {
        self.id = id
        self.name = name
        self.lengthCM = lengthCM
        self.imageName = imageName
        self.alignsZeroToSubject = alignsZeroToSubject
    }

    public static let catalog: [ScaleReference] = [
        ScaleReference(id: "none", name: "無", lengthCM: nil),
        // BIC Maxi J26 實高 81mm
        ScaleReference(id: "lighter", name: "打火機", lengthCM: 8.1,
                       imageName: "ref-lighter"),
        // 藍白拖 10 號 = 26cm(11 號 27、12 號 28;依實物調整此值)
        ScaleReference(id: "slipper", name: "藍白拖", lengthCM: 26.0,
                       imageName: "ref-slipper"),
        // 手部量魚板:0→60 刻度 + 底部紅帶,全板實長 63cm(由實拍板像素量得:
        // 0→60=1323px、全板=1389px);0 刻度於圖頂端,預設對齊拍攝物
        ScaleReference(id: "hand-board", name: "手", lengthCM: 63.0,
                       imageName: "ref-hand-board",
                       alignsZeroToSubject: true),
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

/// 量魚板預設擺位:與拍攝物量測線平行、0 刻度端(圖頂端)對齊 A 點,
/// 沿法線偏移 gap 避免遮住拍攝物;之後仍可手動拖移/旋轉。
public enum OverlayPlacement {
    public static func boardPlacement(fishA: PlanePoint, fishB: PlanePoint,
                                      boardLengthPx: Double, gapPx: Double)
        -> (center: PlanePoint, rotationDegrees: Double)? {
        let dx = fishB.x - fishA.x, dy = fishB.y - fishA.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, boardLengthPx > 0 else { return nil }
        let ux = dx / length, uy = dy / length   // 魚方向(A→B)
        let nx = -uy, ny = ux                    // 法線(螢幕座標的側向)
        let center = PlanePoint(x: fishA.x + ux * boardLengthPx / 2 + nx * gapPx,
                                y: fishA.y + uy * boardLengthPx / 2 + ny * gapPx)
        // 板圖自身 0→尾為 +y(頂→底);轉到魚方向 = θ - 90°
        let rotation = atan2(dy, dx) * 180 / Double.pi - 90
        return (center, rotation)
    }
}
