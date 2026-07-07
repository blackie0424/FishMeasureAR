import Foundation

/// 漁獲紀錄的平台無關快照,供統計與 CSV 匯出使用。
/// (App 端由 SwiftData CatchRecord 轉出;Kit 不依賴 SwiftData。)
public struct CatchEntry: Equatable, Sendable {
    public let species: String
    public let lengthCM: Double?
    public let method: String?
    public let capturedAt: Date
    public let latitude: Double?
    public let longitude: Double?
    public let placeName: String?
    public let isSynced: Bool

    public init(species: String, lengthCM: Double?, method: String?,
                capturedAt: Date, latitude: Double?, longitude: Double?,
                placeName: String?, isSynced: Bool) {
        self.species = species
        self.lengthCM = lengthCM
        self.method = method
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.isSynced = isSynced
    }
}
