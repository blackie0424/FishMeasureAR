import CoreLocation

/// 定位服務:授權、單次定位、反向地理編碼。
/// 拒絕授權時所有方法回傳 nil,測量功能不受影響。
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 單次定位,10 秒逾時
    func currentLocation() async -> CLLocation? {
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else { return nil }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.continuation?.resume(returning: self?.manager.location)
                self?.continuation = nil
            }
        }
    }

    /// 反向地理編碼(離線時回傳 nil,之後可由日誌補查)
    func reverseGeocode(_ location: CLLocation?) async -> String? {
        guard let location else { return nil }
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        else { return nil }

        // 例:「台東縣 蘭嶼鄉」
        return [placemark.administrativeArea, placemark.locality, placemark.subLocality]
            .compactMap { $0 }
            .prefix(2)
            .joined(separator: " ")
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.first)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
