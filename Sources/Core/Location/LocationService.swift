@preconcurrency import CoreLocation

/// 定位服務:授權、單次定位、反向地理編碼。
/// 拒絕授權時所有方法回傳 nil,測量功能不受影響。
/// 綁定 MainActor:CLLocationManager 及其 delegate 皆在主執行緒運作,
/// 也讓內部可變狀態(continuation)符合並行安全規範。
@MainActor
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
            // 10 秒逾時:asyncAfter 於主佇列執行,故可安全 assumeIsolated 回到 MainActor
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finish(with: self.manager.location)
                }
            }
        }
    }

    /// 統一收斂 continuation,確保只 resume 一次
    private func finish(with location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
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
        finish(with: locations.first)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}
