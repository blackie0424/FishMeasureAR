import ARKit
import RealityKit
import SwiftUI
import FishMeasureKit
import os

/// 仿 iOS 測距儀的 AR 兩點量測:
/// 準星(畫面中心)raycast 到表面,按「＋」設定 A、B 點(世界座標錨定,
/// 移動手機點位仍貼在物體上);兩點齊備後畫出 3D 線段並得長度。
/// 點與線是 RealityKit 實體,ARView 快照會自動包含,拍照即合成。
@MainActor
final class TapMeasureSessionController: NSObject, ObservableObject, ARSessionDelegate {

    @Published private(set) var measure = TwoPointMeasure()
    @Published private(set) var reticleHasSurface = false
    /// 設定第一點後,A 點到準星的即時預覽長度(cm)
    @Published private(set) var previewLengthCM: Double?
    /// 量測線中點的畫面座標(數字氣泡直接貼在線上顯示用)
    @Published private(set) var lineMidpointInView: CGPoint?
    @Published private(set) var hasLiDAR = false

    weak var arView: ARView?

    private var worldPoints: [SIMD3<Float>] = []
    private var pointAnchors: [AnchorEntity] = []
    private var lineAnchor: AnchorEntity?
    private var previewAnchor: AnchorEntity?
    private var previewLine: ModelEntity?
    /// 幀節流:在 delegate 執行緒先過濾,避免每幀都往 MainActor 丟 Task
    private let frameGate = OSAllocatedUnfairLock(initialState: 0)
    private let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                category: "ar")

    var lengthCM: Double? { measure.lengthCM }

    // MARK: Session

    func start(on arView: ARView) {
        logger.info("ARSession start (LiDAR pending check)")
        self.arView = arView
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            hasLiDAR = true
        }
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        logger.info("ARSession running (LiDAR=\(self.hasLiDAR))")
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

    /// 更新準星狀態、預覽線與數字氣泡位置
    private func tick() {
        let hit = centerWorldPoint()
        reticleHasSurface = hit != nil

        switch worldPoints.count {
        case 1:
            if let hit, let arView {
                updatePreviewLine(from: worldPoints[0], to: hit)
                previewLengthCM = Double(simd_distance(worldPoints[0], hit)) * 100
                if let a = arView.project(worldPoints[0]) {
                    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
                    lineMidpointInView = CGPoint(x: (a.x + center.x) / 2,
                                                 y: (a.y + center.y) / 2)
                } else {
                    lineMidpointInView = nil
                }
            } else {
                previewLengthCM = nil
                lineMidpointInView = nil
            }
        case 2:
            if let arView,
               let a = arView.project(worldPoints[0]),
               let b = arView.project(worldPoints[1]) {
                lineMidpointInView = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            } else {
                lineMidpointInView = nil
            }
        default:
            previewLengthCM = nil
            lineMidpointInView = nil
        }
    }

    // MARK: 量測操作

    func addPoint() {
        guard measure.canAddPoint,
              let world = centerWorldPoint(),
              let arView else { return }

        worldPoints.append(world)
        measure.addPoint(WorldPoint(x: Double(world.x),
                                    y: Double(world.y),
                                    z: Double(world.z)))

        let anchor = AnchorEntity(world: world)
        anchor.addChild(Self.makeDot())
        arView.scene.addAnchor(anchor)
        pointAnchors.append(anchor)

        if worldPoints.count == 2 {
            removePreview()
            drawLine(from: worldPoints[0], to: worldPoints[1])
        }
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
        removePreview()
        previewLengthCM = nil
        lineMidpointInView = nil
    }

    /// 兩端點投影回目前畫面座標(拍照時定位長度標籤用)
    func projectedEndpoints() -> (CGPoint, CGPoint)? {
        guard let arView, worldPoints.count == 2,
              let a = arView.project(worldPoints[0]),
              let b = arView.project(worldPoints[1]) else { return nil }
        return (a, b)
    }

    // MARK: 準星 raycast

    private func centerWorldPoint() -> SIMD3<Float>? {
        guard let arView, arView.bounds.size != .zero else { return nil }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let result = arView.raycast(from: center,
                                          allowing: .estimatedPlane,
                                          alignment: .any).first else { return nil }
        let t = result.worldTransform.columns.3
        return SIMD3(t.x, t.y, t.z)
    }

    // MARK: 3D 實體

    private func drawLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let length = simd_distance(a, b)
        guard length > 0.001 else { return }
        let entity = ModelEntity(
            mesh: .generateBox(size: [length, 0.0025, 0.0025]),
            materials: [SimpleMaterial(color: .white, isMetallic: false)])
        entity.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(b - a))
        let anchor = AnchorEntity(world: (a + b) / 2)
        anchor.addChild(entity)
        arView?.scene.addAnchor(anchor)
        lineAnchor = anchor
    }

    private func updatePreviewLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let length = simd_distance(a, b)
        guard length > 0.001, let arView else { return }

        if previewAnchor == nil {
            // 單位長線段,之後只改 scale/orientation,避免每幀重建 mesh
            let entity = ModelEntity(
                mesh: .generateBox(size: [1, 0.0018, 0.0018]),
                materials: [SimpleMaterial(color: .white.withAlphaComponent(0.7),
                                           isMetallic: false)])
            let anchor = AnchorEntity(world: SIMD3<Float>.zero)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            previewAnchor = anchor
            previewLine = entity
        }
        previewAnchor?.position = (a + b) / 2
        previewLine?.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(b - a))
        previewLine?.scale = [length, 1, 1]
    }

    private func removeLine() {
        if let lineAnchor { arView?.scene.removeAnchor(lineAnchor) }
        lineAnchor = nil
    }

    private func removePreview() {
        if let previewAnchor { arView?.scene.removeAnchor(previewAnchor) }
        previewAnchor = nil
        previewLine = nil
    }

    private static func makeDot() -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: 0.004),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)])
    }
}
