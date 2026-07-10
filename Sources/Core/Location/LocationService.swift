@preconcurrency import CoreLocation
import os

/// 定位服務:授權、單次定位、反向地理編碼。
/// 拒絕授權時所有方法回傳 nil,測量功能不受影響。
/// 綁定 MainActor:CLLocationManager 及其 delegate 皆在主執行緒運作,
/// 也讓內部可變狀態(continuations)符合並行安全規範。
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// 支援多個併發呼叫者:全部排隊,一次定位結果同時回覆。
    /// (先前單一 continuation 版本在重疊呼叫時會覆寫,第一個 await 永遠卡住)
    private var continuations: [CheckedContinuation<CLLocation?, Never>] = []
    private let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                category: "location")

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

    /// 單次定位,10 秒逾時;併發呼叫共享同一次結果。
    func currentLocation() async -> CLLocation? {
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else { return nil }

        logger.info("currentLocation requested (waiters=\(self.continuations.count))")
        return await withCheckedContinuation { cont in
            continuations.append(cont)
            if continuations.count == 1 {
                manager.requestLocation()
            }
            // 10 秒逾時:asyncAfter 於主佇列執行,故可安全 assumeIsolated 回到 MainActor
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.continuations.isEmpty else { return }
                    self.logger.warning("currentLocation timeout, using last known")
                    self.finish(with: self.manager.location)
                }
            }
        }
    }

    /// 統一收斂:回覆所有等待者,確保每個 continuation 只 resume 一次
    private func finish(with location: CLLocation?) {
        let waiters = continuations
        continuations.removeAll()
        waiters.forEach { $0.resume(returning: location) }
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
    // nonisolated 滿足協定的非隔離需求(Swift 6 conformance),再跳回 MainActor 處理

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        Task { @MainActor in self.finish(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.warning("didFailWithError: \(error.localizedDescription)")
            self.finish(with: nil)
        }
    }
}
