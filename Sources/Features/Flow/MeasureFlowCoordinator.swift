import SwiftUI
import SwiftData
import CoreLocation
import FishMeasureKit

/// 工作流協調者:持有 MeasureFlow 狀態機(FishMeasureKit,純邏輯)、
/// 當前量測中的照片、連拍待量佇列,並負責儲存(照片+SwiftData)。
@MainActor
final class MeasureFlowCoordinator: ObservableObject {

    // MARK: 狀態

    @Published private(set) var flow = MeasureFlow()
    @Published var currentShot: Shot?
    @Published private(set) var pendingQueue: [PendingShot] = []
    @Published private(set) var toast: String?
    @Published var selectedReference: ScaleReference = ScaleReference.catalog[0]

    let locationService = LocationService()
    private let captureService = CaptureService()
    private var toastTask: Task<Void, Never>?

    /// 量測中的一張照片。座標一律為影像像素座標(原點左上)。
    struct Shot {
        let image: UIImage
        let capturedAt: Date
        let location: CLLocation?
        let placeName: String?
        /// AR 提供的公制長度(nil = 需比例尺步驟)
        let arLengthCM: Double?
        /// AR 端點原始位置(供拖曳後按比例重算)
        let originalFishA: PlanePoint?
        let originalFishB: PlanePoint?
        var fishA: PlanePoint
        var fishB: PlanePoint
        var scaleA: PlanePoint
        var scaleB: PlanePoint
        let measureMethod: String

        init(image: UIImage, capturedAt: Date,
             location: CLLocation?, placeName: String?,
             arLengthCM: Double?, arEndpoints: (PlanePoint, PlanePoint)?,
             measureMethod: String) {
            let w = image.size.width, h = image.size.height
            self.image = image
            self.capturedAt = capturedAt
            self.location = location
            self.placeName = placeName
            self.arLengthCM = arLengthCM
            self.originalFishA = arEndpoints?.0
            self.originalFishB = arEndpoints?.1
            self.fishA = arEndpoints?.0 ?? PlanePoint(x: w * 0.25, y: h * 0.5)
            self.fishB = arEndpoints?.1 ?? PlanePoint(x: w * 0.75, y: h * 0.5)
            self.scaleA = PlanePoint(x: w * 0.35, y: h * 0.75)
            self.scaleB = PlanePoint(x: w * 0.65, y: h * 0.75)
            self.measureMethod = measureMethod
        }
    }

    /// 連拍模式暫存的照片(App 結束即失效;持久化列為下一迭代)
    struct PendingShot: Identifiable {
        let id = UUID()
        let image: UIImage
        let capturedAt: Date
        let location: CLLocation?
        let placeName: String?
    }

    // MARK: 導出量測值

    /// 目前端點對應的魚長(cm)。
    /// AR 有公制長度 → 以原端點推 cm/px 再按拖曳後距離換算;
    /// 否則需比例尺線 + 已知尺寸參照物。
    var adjustedLengthCM: Double? {
        guard let shot = currentShot else { return nil }
        if let ar = shot.arLengthCM,
           let oa = shot.originalFishA, let ob = shot.originalFishB,
           let cmPerPx = PixelScaleMeasurement.cmPerPixel(lengthCM: ar,
                                                          pointA: oa, pointB: ob) {
            return PixelScaleMeasurement.length(from: shot.fishA, to: shot.fishB,
                                                cmPerPixel: cmPerPx)
        }
        guard let refCM = selectedReference.lengthCM else { return nil }
        return PixelScaleMeasurement.lengthCM(fishA: shot.fishA, fishB: shot.fishB,
                                              scaleA: shot.scaleA, scaleB: shot.scaleB,
                                              scaleLengthCM: refCM)
    }

    var hasMetricLength: Bool {
        currentShot?.arLengthCM != nil && currentShot?.originalFishA != nil
    }

    // MARK: 拍照

    func takeShot(from controller: MeasureSessionController) {
        guard let arView = controller.arView else { return }
        let arLength = controller.lengthCM
        let endpointsInView = controller.endpointsInView
        let method = controller.hasLiDAR ? "auto-lidar" : "auto-plane"
        let viewSize = arView.bounds.size

        Task { @MainActor in
            guard let image = try? await captureService.snapshot(from: arView) else {
                showToast("拍攝失敗,請再試一次")
                return
            }
            let location = await locationService.currentLocation()
            let place = await locationService.reverseGeocode(location)

            switch flow.mode {
            case .burst:
                pendingQueue.append(PendingShot(image: image, capturedAt: .now,
                                                location: location, placeName: place))
                flow.shutterPressed()
            case .single:
                // AR 端點(view 座標)→ 快照影像像素座標
                var arEndpoints: (PlanePoint, PlanePoint)? = nil
                if let (v1, v2) = endpointsInView, arLength != nil,
                   viewSize.width > 0, viewSize.height > 0 {
                    let sx = image.size.width / viewSize.width
                    let sy = image.size.height / viewSize.height
                    arEndpoints = (PlanePoint(x: v1.x * sx, y: v1.y * sy),
                                   PlanePoint(x: v2.x * sx, y: v2.y * sy))
                }
                currentShot = Shot(image: image, capturedAt: .now,
                                   location: location, placeName: place,
                                   arLengthCM: arLength, arEndpoints: arEndpoints,
                                   measureMethod: method)
                flow.shutterPressed()
            }
        }
    }

    // MARK: 狀態機轉發(讓 View 不直接改 flow)

    func setMode(_ mode: CaptureMode) { flow.setMode(mode) }
    func endBurst() { flow.endBurst() }
    func goToStats() { flow.goToStats() }
    func advanceFromScale() { flow.advanceFromScale() }
    func selectSpecies(_ s: String) { flow.selectSpecies(s) }
    func selectMethod(_ m: String) { flow.selectMethod(m) }

    func backToCapture() {
        currentShot = nil
        flow.backToCapture()
    }

    func backToAdjustFish() { flow.backToAdjustFish() }

    func advanceFromAdjustFish() {
        flow.advanceFromAdjustFish(hasMetricLength: hasMetricLength)
    }

    /// 統計頁「去量」:取佇列第一張開始量測(儲存成功才移出佇列)。
    func beginPendingMeasurement() {
        guard let pending = pendingQueue.first else { return }
        currentShot = Shot(image: pending.image, capturedAt: pending.capturedAt,
                           location: pending.location, placeName: pending.placeName,
                           arLengthCM: nil, arEndpoints: nil,
                           measureMethod: "manual-scale")
        flow.startMeasuringPending()
    }

    // MARK: 儲存

    func saveRecord(to destination: MeasureFlow.SaveDestination,
                    in context: ModelContext) async {
        guard let shot = currentShot else { return }
        guard let species = flow.selectedSpecies else {
            _ = flow.save(to: destination)   // 標記魚種必填
            return
        }

        let length = adjustedLengthCM
        let settings = AppSettings()
        let fuzz = settings.fuzzLocation && shot.location != nil
        let storedLocation = fuzz ? shot.location?.fuzzed() : shot.location
        let usedReference = !hasMetricLength && selectedReference.lengthCM != nil
            ? [selectedReference.id] : []

        do {
            let localID = try await captureService.save(image: shot.image,
                                                        lengthCM: length,
                                                        location: shot.location,
                                                        placeName: shot.placeName)
            let record = CatchRecord(
                lengthCM: length,
                measureMethod: shot.arLengthCM != nil ? shot.measureMethod : "manual-scale",
                species: species,
                fishingMethod: flow.selectedMethod,
                location: storedLocation,
                placeName: shot.placeName,
                isLocationFuzzed: fuzz,
                photoLocalID: localID,
                referenceObjectsUsed: usedReference)
            context.insert(record)

            if flow.isMeasuringPending, !pendingQueue.isEmpty {
                pendingQueue.removeFirst()
            }
            _ = flow.save(to: destination)
            currentShot = nil
            selectedReference = ScaleReference.catalog[0]
            showToast("已儲存至本機 · 有網路時自動同步")
        } catch {
            showToast("儲存失敗:\(error.localizedDescription)")
        }
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
