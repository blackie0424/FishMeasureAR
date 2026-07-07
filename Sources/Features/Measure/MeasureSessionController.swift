import ARKit
import RealityKit
import SwiftUI
import Combine

/// 將未標記 Sendable 的參照型別包裝為可安全跨執行緒傳遞。
/// 僅用於「建立後即唯讀」的相機資料(如 CVPixelBuffer),於背景佇列僅做讀取。
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// 測量狀態(供 UI 顯示)
enum MeasureStatus: Equatable {
    case searching          // 黃:偵測中
    case measuring          // 黃:已偵測、讀值未穩定
    case stable             // 綠:穩定,可拍攝
    case badDistance        // 紅:太近/太遠/平面未定
}

/// AR 測量核心:管理 ARSession、每 N 幀跑分割、
/// LiDAR 反投影(或非 LiDAR raycast 降級)、發布測量結果。
@MainActor
final class MeasureSessionController: NSObject, ObservableObject, ARSessionDelegate {

    @Published var status: MeasureStatus = .searching
    @Published var lengthCM: Double? = nil
    @Published var endpointsInView: (CGPoint, CGPoint)? = nil  // 疊加線用(view 座標)
    @Published var hasLiDAR = false

    weak var arView: ARView?

    private var smoother = MeasurementSmoother()
    private var frameCounter = 0
    private let processEveryNFrames = 5
    private var isProcessing = false
    private let visionQueue = DispatchQueue(label: "fishmeasure.vision", qos: .userInitiated)

    /// 最近一次的世界座標端點(拍攝與參照物放置會用到)
    private(set) var worldEndpoints: (SIMD3<Float>, SIMD3<Float>)? = nil

    // MARK: - Session lifecycle

    func start(on arView: ARView) {
        self.arView = arView
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]

        if ARWorldTrackingConfiguration.supportsFrameSemantics([.smoothedSceneDepth]) {
            config.frameSemantics.insert(.smoothedSceneDepth)
            config.frameSemantics.insert(.sceneDepth)
            hasLiDAR = true
        }

        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        arView?.session.pause()
        smoother.reset()
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            await self.processFrameIfNeeded(frame)
        }
    }

    private func processFrameIfNeeded(_ frame: ARFrame) async {
        frameCounter += 1
        guard frameCounter % processEveryNFrames == 0, !isProcessing else { return }
        isProcessing = true

        // capturedImage 為 landscape,App 固定 portrait → .right
        // CVPixelBuffer 未標記 Sendable,以包裝跨執行緒(唯讀)傳遞至 vision 佇列
        let pixelBuffer = UncheckedSendable(frame.capturedImage)
        let result = await detectEndpoints(in: pixelBuffer)
        // 回到 MainActor;frame 全程未離開主執行緒隔離域
        handleSegmentation(result, frame: frame)
        isProcessing = false
    }

    /// 於 vision 佇列執行分割,避免阻塞主執行緒;結果(Sendable)再回傳 MainActor。
    private func detectEndpoints(in pixelBuffer: UncheckedSendable<CVPixelBuffer>)
        async -> FishSegmentation.Result? {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                let result = FishSegmentation.detectEndpoints(in: pixelBuffer.value,
                                                              orientation: .right)
                continuation.resume(returning: result)
            }
        }
    }

    private func handleSegmentation(_ result: FishSegmentation.Result?, frame: ARFrame) {
        guard let result else {
            status = .searching
            return
        }

        // 注意:分割以 orientation 校正後座標回傳,需轉回 capturedImage 原始(landscape)座標
        let p1 = rotateBackToCapturedImage(result.p1, frame: frame)
        let p2 = rotateBackToCapturedImage(result.p2, frame: frame)

        var w1: SIMD3<Float>?
        var w2: SIMD3<Float>?

        if hasLiDAR {
            w1 = DepthUnprojector.unproject(pixel: p1, frame: frame)
            w2 = DepthUnprojector.unproject(pixel: p2, frame: frame)
        }
        // 非 LiDAR 或深度失敗 → raycast 降級
        if w1 == nil || w2 == nil {
            let v1 = viewPoint(fromCaptured: p1, frame: frame)
            let v2 = viewPoint(fromCaptured: p2, frame: frame)
            w1 = raycastWorld(at: v1)
            w2 = raycastWorld(at: v2)
        }

        guard let w1, let w2 else {
            status = .badDistance
            return
        }

        worldEndpoints = (w1, w2)
        let length = Double(simd_distance(w1, w2))

        // 合理性過濾:2cm–200cm
        guard (0.02...2.0).contains(length) else {
            status = .badDistance
            return
        }

        smoother.push(length)
        if let median = smoother.median {
            lengthCM = median * 100
        }
        status = smoother.isStable ? .stable : .measuring

        endpointsInView = (viewPoint(fromCaptured: p1, frame: frame),
                           viewPoint(fromCaptured: p2, frame: frame))
    }

    // MARK: - 座標轉換

    /// 分割結果(portrait 校正座標)→ capturedImage 原始 landscape 像素座標
    private func rotateBackToCapturedImage(_ p: CGPoint, frame: ARFrame) -> CGPoint {
        let w = CGFloat(CVPixelBufferGetWidth(frame.capturedImage))
        // orientation .right 的逆轉換:portrait(x,y) → landscape(x', y') = (y, W_portrait - x)
        // portrait 寬 = landscape 高
        let portraitWidth = CGFloat(CVPixelBufferGetHeight(frame.capturedImage))
        _ = w
        return CGPoint(x: p.y, y: portraitWidth - p.x)
    }

    /// capturedImage 像素座標 → ARView 顯示座標(用 displayTransform)
    private func viewPoint(fromCaptured p: CGPoint, frame: ARFrame) -> CGPoint {
        guard let arView, arView.bounds.size != .zero else { return .zero }
        let imageSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage),
                               height: CVPixelBufferGetHeight(frame.capturedImage))
        // 正規化 → displayTransform → view 座標
        let normalized = CGPoint(x: p.x / imageSize.width, y: p.y / imageSize.height)
        let transform = frame.displayTransform(for: .portrait,
                                               viewportSize: arView.bounds.size)
        let displayed = normalized.applying(transform)
        return CGPoint(x: displayed.x * arView.bounds.width,
                       y: displayed.y * arView.bounds.height)
    }

    private func raycastWorld(at viewPoint: CGPoint) -> SIMD3<Float>? {
        guard let arView,
              let result = arView.raycast(from: viewPoint,
                                          allowing: .estimatedPlane,
                                          alignment: .horizontal).first
        else { return nil }
        let t = result.worldTransform.columns.3
        return SIMD3(t.x, t.y, t.z)
    }
}
