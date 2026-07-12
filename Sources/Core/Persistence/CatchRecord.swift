import SwiftData
import CoreLocation
import Foundation
import FishMeasureKit

@Model
final class CatchRecord {
    var id: UUID
    var createdAt: Date
    /// ⚠ Schema 守則:新增「非 optional」屬性必須在宣告層帶預設值(= xxx),
    /// 否則 SwiftData 對既有資料庫遷移失敗 → store 重建 → 使用者資料全失
    /// (2026-07-11 photoLocalIDs 未帶預設值造成日誌清空的教訓)。
    /// 未量測(連拍待量或無比例尺)時為 nil
    var lengthCM: Double?
    var measureMethod: String        // "auto-lidar" | "auto-plane" | "manual-scale"
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var placeName: String?
    /// 使用者填寫的實際地點(如「開元港」);自動反向地理編碼只到鄉鎮層級
    var placeNote: String? = nil
    var isLocationFuzzed: Bool
    var photoLocalID: String
    /// 整組照片(依序:原圖/測量版/比例物版);舊資料為空陣列
    var photoLocalIDs: [String] = []
    var speciesName: String?
    var fishingMethod: String?       // 岸釣/船釣/磯釣/刺網/一支釣
    var note: String?
    /// 魚聲錄音檔名(App Documents 下;nil = 未錄)
    var audioFileName: String? = nil
    var referenceObjectsUsed: [String] = []
    /// 量測端點(原圖像素座標,[ax, ay, bx, by]):
    /// 供事後替換比例尺物件時換算 cm/px;舊資料為空陣列(功能停用)
    var fishEndpointsPx: [Double] = []
    /// 之後上傳調查平台用;目前一律 false(⟳ 待傳)
    var isSynced: Bool = false

    /// - Parameters:
    ///   - location: 欲儲存的座標。隱私模式的模糊化由呼叫端先行處理,
    ///     並以 isLocationFuzzed 如實標記,模型本身不讀取全域設定。
    init(lengthCM: Double?,
         measureMethod: String,
         species: String?,
         fishingMethod: String?,
         location: CLLocation?,
         placeName: String?,
         isLocationFuzzed: Bool,
         photoLocalID: String,
         referenceObjectsUsed: [String]) {
        self.id = UUID()
        self.createdAt = .now
        self.lengthCM = lengthCM
        self.measureMethod = measureMethod
        self.latitude = location?.coordinate.latitude
        self.longitude = location?.coordinate.longitude
        self.horizontalAccuracy = location?.horizontalAccuracy
        self.placeName = placeName
        self.isLocationFuzzed = isLocationFuzzed
        self.photoLocalID = photoLocalID
        self.photoLocalIDs = []
        self.speciesName = species
        self.fishingMethod = fishingMethod
        self.note = nil
        self.referenceObjectsUsed = referenceObjectsUsed
        self.isSynced = false
    }
}

extension CatchRecord {
    /// 詳情頁瀏覽用:整組照片,舊紀錄退回單張
    var allPhotoIDs: [String] {
        photoLocalIDs.isEmpty ? [photoLocalID] : photoLocalIDs
    }

    /// 顯示用地點:使用者填寫優先,退回自動地理編碼
    var displayPlace: String? {
        placeNote ?? placeName
    }

    /// 量測方式的顯示文字(不給使用者看內部代號)
    var measureMethodLabel: String {
        switch measureMethod {
        case "tap-lidar":    return "AR 測距(LiDAR)"
        case "tap-plane":    return "AR 測距"
        case "manual-scale": return "比例尺換算"
        default:              return measureMethod
        }
    }

    /// 事後替換比例尺所需資料是否齊全
    var canEditReference: Bool {
        lengthCM != nil && fishEndpointsPx.count == 4 && !photoLocalIDs.isEmpty
    }

    var fishEndpointA: PlanePoint? {
        fishEndpointsPx.count == 4
            ? PlanePoint(x: fishEndpointsPx[0], y: fishEndpointsPx[1]) : nil
    }

    var fishEndpointB: PlanePoint? {
        fishEndpointsPx.count == 4
            ? PlanePoint(x: fishEndpointsPx[2], y: fishEndpointsPx[3]) : nil
    }

    var lengthLabel: String {
        lengthCM.map { String(format: "%.1f cm", $0) } ?? "未量測"
    }
}
