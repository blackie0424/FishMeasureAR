import ARKit
import RealityKit
import SwiftUI
import FishMeasureKit
import os

/// AR 兩點量測(構圖先行版):
/// 直接點擊畫面上的物體端點設定 A、B(任意位置取點,手機不必移動,
/// 構圖不被打斷);點位以世界座標錨定,兩點齊備後畫出 3D 線段並得長度。
/// 快照時 3D 實體會隱藏,照片上的線由確認頁定位、存檔時合成。
@MainActor
final class TapMeasureSessionController: NSObject, ObservableObject, ARSessionDelegate {

    @Published private(set) var measure = TwoPointMeasure()
    @Published private(set) var reticleHasSurface = false
    /// 量測線中點的畫面座標(數字氣泡直接貼在線上顯示用)
    @Published private(set) var lineMidpointInView: CGPoint?
    @Published private(set) var hasLiDAR = false

    /// 強持有並跨畫面重用:回到拍攝畫面時不重置世界地圖,
    /// 免去每拍一張就重新等待平面偵測(「等準星變綠很久」的主因之一)。
    private(set) var arView: ARView?

    private var worldPoints: [SIMD3<Float>] = []
    private var pointAnchors: [AnchorEntity] = []
    private var lineAnchor: AnchorEntity?
    /// 幀節流:在 delegate 執行緒先過濾,避免每幀都往 MainActor 丟 Task
    private let frameGate = OSAllocatedUnfairLock(initialState: 0)
    /// 重定位卡死看門狗:limited(.relocalizing) 持續超過門檻就整個重置
    private var relocalizingSince: Date?
    private let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                category: "ar")

    /// 量測線/點的亮青色(UnlitMaterial 不受場景光照,不會被壓灰)
    static let lineColor = UIColor(red: 0.21, green: 0.77, blue: 0.94, alpha: 1)

    var lengthCM: Double? { measure.lengthCM }

    // MARK: Session

    /// 首次建立 ARView 並全新啟動;之後重用同一個 view、
    /// 以不帶 reset 的 run 快速回復(保留世界地圖,約一秒內重定位)。
    func makeOrReuseARView() -> ARView {
        if let arView {
            logger.info("ARSession resume (reuse, no reset)")
            arView.session.run(configuration())
            return arView
        }
        let view = ARView(frame: .zero)
        view.renderOptions.insert(.disableMotionBlur)
        // 所有互動都在 SwiftUI 疊層(氣泡拖曳/按鈕);ARView 本身不收觸控,
        // 否則 UIKit 點擊判定讓它優先吃掉手勢,疊在上面的 SwiftUI 拖曳收不到
        view.isUserInteractionEnabled = false
        arView = view
        view.session.delegate = self
        view.session.run(configuration(),
                         options: [.resetTracking, .removeExistingAnchors])
        logger.info("ARSession started fresh (LiDAR=\(self.hasLiDAR))")
        return view
    }

    private func configuration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            hasLiDAR = true
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        return config
    }

    func pause() {
        logger.info("ARSession pause")
        arView?.session.pause()
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 每 3 幀更新一次(~20Hz)就足夠順暢
        let n = frameGate.withLock { count -> Int in
            count += 1
            return count
        }
        guard n % 3 == 0 else { return }
        Task { @MainActor in self.tick() }
    }

    /// 更新 AR 就緒狀態(畫面中心探測,供提示文字用)與數字氣泡位置
    private func tick() {
        watchdogCheckTracking()

        reticleHasSurface = worldPoint(atView: viewCenter()) != nil

        if worldPoints.count == 2, let arView,
           let a = arView.project(worldPoints[0]),
           let b = arView.project(worldPoints[1]) {
            lineMidpointInView = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        } else {
            lineMidpointInView = nil
        }
    }

    private func viewCenter() -> CGPoint {
        guard let arView else { return .zero }
        return CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    }

    // MARK: Session 復原(切到相簿再回來、相機被搶用等情境)

    /// 重定位卡超過 2.5 秒就整個重置——寧可重新掃描,也不要準星永遠灰著像當機。
    private func watchdogCheckTracking() {
        guard let state = arView?.session.currentFrame?.camera.trackingState else { return }
        if case .limited(.relocalizing) = state {
            if let since = relocalizingSince {
                if Date().timeIntervalSince(since) > 2.5 {
                    logger.warning("relocalizing stuck > 2.5s, restarting session")
                    relocalizingSince = nil
                    restartSession()
                }
            } else {
                relocalizingSince = Date()
            }
        } else {
            relocalizingSince = nil
        }
    }

    /// Session 死亡(如相機被其他 App 佔用後歸還)不會自己復活,必須手動重跑
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("ARSession failed: \(error.localizedDescription) — restarting")
            self.restartSession()
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.logger.info("ARSession interrupted") }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.logger.info("ARSession interruption ended — restarting")
            self.restartSession()
        }
    }

    /// 全新重跑:中斷後舊點位已不可信,一併清除
    private func restartSession() {
        reset()
        arView?.session.run(configuration(),
                            options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: 量測操作

    /// 於畫面任意位置設點(點哪量哪,構圖不必移動)。
    /// 回傳是否成功(該處抓不到表面時 false,由 UI 提示)。
    @discardableResult
    func addPoint(at viewPoint: CGPoint) -> Bool {
        guard measure.canAddPoint,
              let world = worldPoint(atView: viewPoint),
              let arView else { return false }

        worldPoints.append(world)
        measure.addPoint(WorldPoint(x: Double(world.x),
                                    y: Double(world.y),
                                    z: Double(world.z)))

        let anchor = AnchorEntity(world: world)
        anchor.addChild(Self.makeDot())
        arView.scene.addAnchor(anchor)
        pointAnchors.append(anchor)

        if worldPoints.count == 2 {
            drawLine(from: worldPoints[0], to: worldPoints[1])
        }
        return true
    }

    func undo() {
        guard !worldPoints.isEmpty else { return }
        worldPoints.removeLast()
        measure.undoLastPoint()
        if let anchor = pointAnchors.popLast() {
            arView?.scene.removeAnchor(anchor)
        }
        removeLine()
    }

    func reset() {
        worldPoints.removeAll()
        measure.reset()
        pointAnchors.forEach { arView?.scene.removeAnchor($0) }
        pointAnchors.removeAll()
        removeLine()
        lineMidpointInView = nil
    }

    /// 快照前隱藏 3D 量測實體:AR 錨點在改構圖時可能飄移,
    /// 照片上的線改由「確認測量線」步驟在靜態影像上定位、存檔時合成。
    func setMeasurementVisible(_ visible: Bool) {
        pointAnchors.forEach { $0.isEnabled = visible }
        lineAnchor?.isEnabled = visible
    }

    /// 兩端點投影回目前畫面座標(拍照時定位長度標籤用)
    func projectedEndpoints() -> (CGPoint, CGPoint)? {
        guard let arView, worldPoints.count == 2,
              let a = arView.project(worldPoints[0]),
              let b = arView.project(worldPoints[1]) else { return nil }
        return (a, b)
    }

    // MARK: 任意位置取點(三段後備)

    private func worldPoint(atView point: CGPoint) -> SIMD3<Float>? {
        guard let arView, arView.bounds.size != .zero else { return nil }

        // 1) 平面 raycast:平面已知時最穩定
        if let result = arView.raycast(from: point,
                                       allowing: .estimatedPlane,
                                       alignment: .any).first {
            let t = result.worldTransform.columns.3
            return SIMD3(t.x, t.y, t.z)
        }
        // 2) LiDAR 深度直接反投影:即開即用,不必等平面偵測,
        //    對貼在魚體(濕滑/低特徵)上的點也更準
        if let world = depthWorldPoint(atView: point) {
            return world
        }
        // 3) 特徵點(非 LiDAR 的最後手段;API 已棄用但仍可用)
        if let hit = arView.hitTest(point, types: .featurePoint).first {
            let t = hit.worldTransform.columns.3
            return SIMD3(t.x, t.y, t.z)
        }
        return nil
    }

    /// view 座標 → 逆 displayTransform → capturedImage 像素 → LiDAR 深度反投影
    private func depthWorldPoint(atView point: CGPoint) -> SIMD3<Float>? {
        guard hasLiDAR, let arView,
              let frame = arView.session.currentFrame else { return nil }
        let viewSize = arView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let imageW = CGFloat(CVPixelBufferGetWidth(frame.capturedImage))
        let imageH = CGFloat(CVPixelBufferGetHeight(frame.capturedImage))
        let inverse = frame.displayTransform(for: .portrait,
                                             viewportSize: viewSize).inverted()
        let norm = CGPoint(x: point.x / viewSize.width,
                           y: point.y / viewSize.height).applying(inverse)
        let pixel = CGPoint(x: norm.x * imageW, y: norm.y * imageH)
        return DepthUnprojector.unproject(pixel: pixel, frame: frame)
    }

    // MARK: 3D 實體

    private func drawLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let length = simd_distance(a, b)
        guard length > 0.001 else { return }
        let entity = ModelEntity(
            mesh: .generateBox(size: [length, 0.003, 0.003]),
            materials: [UnlitMaterial(color: Self.lineColor)])
        entity.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(b - a))
        let anchor = AnchorEntity(world: (a + b) / 2)
        anchor.addChild(entity)
        arView?.scene.addAnchor(anchor)
        lineAnchor = anchor
    }

    private func removeLine() {
        if let lineAnchor { arView?.scene.removeAnchor(lineAnchor) }
        lineAnchor = nil
    }

    private static func makeDot() -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: 0.005),
                    materials: [UnlitMaterial(color: .white)])
    }
}
