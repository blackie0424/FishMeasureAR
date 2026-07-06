import SwiftData
import CoreLocation
import Foundation

@Model
final class CatchRecord {
    var id: UUID
    var createdAt: Date
    var lengthCM: Double
    var measureMethod: String        // "auto-lidar" | "auto-plane" | "manual"
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var placeName: String?
    var isLocationFuzzed: Bool
    var photoLocalID: String
    var speciesName: String?
    var note: String?
    var referenceObjectsUsed: [String]

    init(lengthCM: Double,
         measureMethod: String,
         location: CLLocation?,
         placeName: String?,
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
        self.isLocationFuzzed = AppSettings().fuzzLocation
        self.photoLocalID = photoLocalID
        self.speciesName = nil
        self.note = nil
        self.referenceObjectsUsed = referenceObjectsUsed
    }
}
