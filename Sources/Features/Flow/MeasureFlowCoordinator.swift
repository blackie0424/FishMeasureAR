import SwiftUI
import SwiftData
import CoreLocation
import FishMeasureKit
import os

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
    /// 儲存進行中(表單顯示旋轉指示、鎖定按鈕防重複點擊)
    @Published private(set) var isSaving = false

    // MARK: 參照物疊圖(拍照後在表單擺放,存檔時等比合成)

    @Published private(set) var overlayReference: ScaleReference?
    @Published private(set) var overlayImage: UIImage?
    /// 疊圖中心(影像像素座標),編輯頁拖曳更新
    @Published var overlayCenter: PlanePoint?
    /// 疊圖角度(度;兩指旋轉或 90° 快轉鈕),存檔同角度合成
    @Published var overlayRotationDegrees: Double = 0

    let locationService = LocationService()
    /// 跨畫面共用:AR session 不隨畫面切換銷毀,回到拍攝免重新等待平面偵測
    let tapController = TapMeasureSessionController()
    private let captureService = CaptureService()
    private var toastTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                category: "flow")

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
        /// 照片是否已含量測線與長度標籤(現行流程一律存檔時才合成 = false)
        let labelComposited: Bool
        /// 拍攝畫面上氣泡被拖曳的偏移(影像像素);nil = 用預設擺位邏輯
        let labelOffset: PlanePoint?

        init(image: UIImage, capturedAt: Date,
             location: CLLocation?, placeName: String?,
             arLengthCM: Double?, arEndpoints: (PlanePoint, PlanePoint)?,
             measureMethod: String, labelComposited: Bool = false,
             labelOffset: PlanePoint? = nil) {
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
            self.labelComposited = labelComposited
            self.labelOffset = labelOffset
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

    /// 這張照片的 cm/px(疊圖等比縮放用):量測長度 ÷ 端點像素距離
    var shotCMPerPixel: Double? {
        guard let shot = currentShot, let length = adjustedLengthCM else { return nil }
        return PixelScaleMeasurement.cmPerPixel(lengthCM: length,
                                                pointA: shot.fishA,
                                                pointB: shot.fishB)
    }

    /// 疊圖在照片上的長邊像素(依實際 cm 等比)
    var overlayLongSidePx: Double? {
        guard let refCM = overlayReference?.lengthCM,
              let cmPerPx = shotCMPerPixel else { return nil }
        return PixelScaleMeasurement.pixelLength(forCM: refCM, cmPerPixel: cmPerPx)
    }

    /// 選擇/取消參照物疊圖;首次選擇時去背並置於照片中下方
    func selectOverlay(_ reference: ScaleReference?) {
        guard let reference, let imageName = reference.imageName else {
            overlayReference = nil
            overlayImage = nil
            overlayCenter = nil
            return
        }
        overlayReference = reference
        if overlayCenter == nil, let shot = currentShot {
            overlayCenter = PlanePoint(x: shot.image.size.width * 0.5,
                                       y: shot.image.size.height * 0.78)
        }
        Task { @MainActor in
            overlayImage = await ReferenceCutout.load(named: imageName)
        }
    }

    private func clearOverlay() {
        overlayReference = nil
        overlayImage = nil
        overlayCenter = nil
        overlayRotationDegrees = 0
    }

    // MARK: 拍照(測距儀式:快照已含 3D 點與線段,再合成長度標籤)

    /// - Parameter bubbleOffset: 拍攝畫面上數字氣泡被拖曳的偏移(view 座標),
    ///   存檔合成沿用(換算至影像像素),所見即所得。
    /// 快照時隱藏 3D 量測實體:AR 錨點在改構圖時可能飄移,
    /// 線與標籤改由「確認測量線」步驟在靜態照片上定位、存檔時才合成。
    func takeShot(from controller: TapMeasureSessionController,
                  bubbleOffset: CGSize = .zero) {
        guard let arView = controller.arView else { return }
        let lengthCM = controller.lengthCM
        let endpointsInView = controller.projectedEndpoints()
        let method = controller.hasLiDAR ? "tap-lidar" : "tap-plane"
        let viewSize = arView.bounds.size

        Task { @MainActor in
            controller.setMeasurementVisible(false)
            let raw = try? await captureService.snapshot(from: arView)
            controller.setMeasurementVisible(true)
            guard let raw else {
                showToast("拍攝失敗,請再試一次")
                return
            }
            let location = await locationService.currentLocation()
            let place = await locationService.reverseGeocode(location)

            switch flow.mode {
            case .burst:
                // 連拍只存原始照片入佇列,稍後批次量測
                pendingQueue.append(PendingShot(image: raw, capturedAt: .now,
                                                location: location, placeName: place))
                flow.shutterPressed()
                controller.reset()   // 快照完成後才清點位,準備下一張
            case .single:
                var endpointsPx: (PlanePoint, PlanePoint)? = nil
                var labelOffset: PlanePoint? = nil
                if lengthCM != nil, let (v1, v2) = endpointsInView,
                   viewSize.width > 0, viewSize.height > 0 {
                    let sx = raw.size.width / viewSize.width
                    let sy = raw.size.height / viewSize.height
                    endpointsPx = (PlanePoint(x: v1.x * sx, y: v1.y * sy),
                                   PlanePoint(x: v2.x * sx, y: v2.y * sy))
                    labelOffset = PlanePoint(x: bubbleOffset.width * sx,
                                             y: bubbleOffset.height * sy)
                }
                currentShot = Shot(image: raw, capturedAt: .now,
                                   location: location, placeName: place,
                                   arLengthCM: lengthCM, arEndpoints: endpointsPx,
                                   measureMethod: method,
                                   labelOffset: labelOffset)
                flow.shutterPressed()   // → 確認測量線(靜態照片上可微調)
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
        clearOverlay()
        tapController.reset()   // 清上一尾的點位,世界地圖保留
        flow.backToCapture()
    }

    func backToAdjustFish() { flow.backToAdjustFish() }

    func advanceFromAdjustFish() {
        flow.advanceFromAdjustFish(hasMetricLength: hasMetricLength)
    }

    func advanceFromOverlayEdit() {
        flow.advanceFromOverlayEdit()
    }

    /// 比例尺編輯往回:回「確認測量線」或比例尺換算(shot 保留,不清理)
    func backFromOverlayEdit() {
        flow.backFromOverlayEdit(hasMetricLength: hasMetricLength)
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
        guard !isSaving else { return }   // 防重複點擊
        guard let shot = currentShot else { return }
        guard let species = flow.selectedSpecies else {
            _ = flow.save(to: destination)   // 標記魚種必填
            return
        }
        isSaving = true
        defer { isSaving = false }
        logger.info("saveRecord: start")

        let length = adjustedLengthCM
        // 設定值一律在 MainActor 讀好(@AppStorage 不保證非主執行緒安全),
        // 打包成 Sendable options 再交給背景儲存
        let settings = AppSettings()
        let fuzz = settings.fuzzLocation && shot.location != nil
        let storedLocation = fuzz ? shot.location?.fuzzed() : shot.location
        let exifLocation: CLLocation? = {
            guard let location = shot.location, settings.embedGPSInPhoto else { return nil }
            return settings.fuzzLocation ? location.fuzzed() : location
        }()
        let saveOptions = PhotoSaveOptions(
            watermarkEnabled: settings.watermarkEnabled,
            watermarkPlace: settings.watermarkShowsPlace ? shot.placeName : nil,
            gpsLocation: exifLocation)
        var usedReference = !hasMetricLength && selectedReference.lengthCM != nil
            ? [selectedReference.id] : []

        // 三張一組:1. 原圖(乾淨) 2. 含測量線 3. 原圖+比例物
        let original = shot.image

        // 第三張:比例物疊圖(去背圖依 cm/px 等比,使用者擺放的位置與角度)
        var referencePhoto: UIImage? = nil
        if let overlayImage, let center = overlayCenter,
           let longSide = overlayLongSidePx {
            referencePhoto = ImageAnnotator.drawOverlay(
                overlayImage,
                centeredAt: CGPoint(x: center.x, y: center.y),
                longSidePx: longSide,
                rotationDegrees: overlayRotationDegrees,
                on: original)
            if let id = overlayReference?.id { usedReference.append(id) }
        }

        // 第二張:測量線+端點+標籤(以確認頁最終端點為準,不受 AR 飄移影響)
        var measuredPhoto: UIImage? = nil
        if let length {
            let size = shot.image.size
            // 拍攝時拖過氣泡 → 沿用該偏移;否則用線法線方向的預設擺位
            let labelPos: PlanePoint
            if let offset = shot.labelOffset {
                labelPos = MeasureAnnotationLayout.displayPosition(
                    midpoint: PlanePoint(x: (shot.fishA.x + shot.fishB.x) / 2,
                                         y: (shot.fishA.y + shot.fishB.y) / 2),
                    offsetX: offset.x, offsetY: offset.y,
                    width: Double(size.width), height: Double(size.height),
                    margin: Double(size.width) * 0.06)
            } else {
                labelPos = MeasureAnnotationLayout.labelPosition(
                    p1: shot.fishA, p2: shot.fishB,
                    offset: Double(size.width) * 0.06,
                    width: Double(size.width), height: Double(size.height))
            }
            measuredPhoto = ImageAnnotator.drawMeasurement(
                from: CGPoint(x: shot.fishA.x, y: shot.fishA.y),
                to: CGPoint(x: shot.fishB.x, y: shot.fishB.y),
                label: String(format: "%.1f cm", length),
                labelAt: CGPoint(x: labelPos.x, y: labelPos.y),
                rotationDegrees: settings.bubbleRotationDegrees,
                on: original)
        }

        do {
            logger.info("saveRecord: saving photo set")
            let localID = try await captureService.saveCatchPhotos(
                original: original,
                measured: measuredPhoto,
                reference: referencePhoto,
                options: saveOptions)
            logger.info("saveRecord: inserting record")
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
            clearOverlay()
            tapController.reset()   // 下一尾從乾淨的點位開始
            logger.info("saveRecord: done")
            let count = 1 + (measuredPhoto != nil ? 1 : 0)
                          + (referencePhoto != nil ? 1 : 0)
            showToast("已存 \(count) 張到相簿「FishMeasureAR」")
        } catch CaptureError.photoLibraryDenied {
            logger.error("saveRecord: photo library denied")
            showToast("沒有相簿權限:請到「設定 > FishMeasureAR」開啟照片權限")
        } catch CaptureError.timedOut {
            logger.error("saveRecord: photo save timed out")
            showToast("寫入相簿逾時,照片未儲存,請再試一次")
        } catch {
            logger.error("saveRecord: failed \(error.localizedDescription)")
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
