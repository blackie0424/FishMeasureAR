import SwiftUI
import SwiftData
import RealityKit
import FishMeasureKit

// MARK: - ARView 包裝

struct ARViewContainer: UIViewRepresentable {
    let controller: TapMeasureSessionController

    func makeUIView(context: Context) -> ARView {
        controller.makeOrReuseARView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - 拍照畫面
// 版面:上下黑帶放所有控制項,中間 3:4 相機預覽保持乾淨;
// 預覽區只有準星、貼在量測線上的數字氣泡。
// 操作:唯一主按鈕依情境切換——「＋」設 A、B 點 → 兩點齊備變快門。

struct CaptureView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    @ObservedObject private var controller: TapMeasureSessionController
    @State private var flash = false
    /// 使用者拖曳數字氣泡的偏移(相對線中點;照片合成沿用同值,所見即所得)
    @State private var bubbleOffset: CGSize = .zero
    @GestureState private var bubbleDragDelta: CGSize = .zero
    /// 氣泡角度:垂直俯拍時重力無法判斷橫直向,由使用者手動切換並記住
    @AppStorage("bubbleRotationDegrees") private var bubbleRotation = 0
    @Query private var records: [CatchRecord]

    init(coordinator: MeasureFlowCoordinator) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._controller = ObservedObject(wrappedValue: coordinator.tapController)
    }

    /// 上黑帶固定高度(模式列 + 提示各一行)
    private let topBarHeight: CGFloat = 92

    var body: some View {
        // 三段版面全部明確計算(拍攝畫面已隱藏 Tab bar,全螢幕可用):
        // 上黑帶(固定) + 預覽(寬度撐滿的 4:3,上限 2/3 高) + 下黑帶(吃剩餘)。
        // 不用 aspectRatio/彈性推導——UIViewRepresentable 的 intrinsic
        // 尺寸會讓 SwiftUI 算出不可預期的結果(實機驗證過)。
        GeometryReader { geo in
            let previewH = min(geo.size.width * 4.0 / 3.0,
                               geo.size.height * 0.66)
            VStack(spacing: 0) {
                topBar
                    .frame(width: geo.size.width, height: topBarHeight)
                preview(width: geo.size.width, height: previewH)
                bottomBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height,
                   alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { coordinator.locationService.requestAuthorization() }
        .onDisappear { controller.pause() }
    }

    // MARK: 上黑帶:狀態列 + 提示

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                if coordinator.flow.mode == .burst {
                    burstBadge
                } else {
                    modeToggle
                }
                Spacer()
                rotateBubbleButton
                recordCountButton
            }
            Text(hintText)
                .font(.footnote.bold())
                .foregroundStyle(hintColor)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var hintText: String {
        if coordinator.flow.mode == .burst {
            return "連拍中:按快門拍照,稍後於統計頁補量"
        }
        if !controller.reticleHasSurface && controller.measure.points.isEmpty {
            return "緩慢移動手機,讓準星對到魚身(準星變綠)"
        }
        switch controller.measure.points.count {
        case 0:  return "準星對準吻端,按「＋」標 A 點"
        case 1:  return "移到尾叉,按「＋」標 B 點"
        default: return "完成!可拖曳數字避開魚身,按快門拍照"
        }
    }

    private var hintColor: Color {
        controller.measure.isComplete ? .green : .yellow
    }

    // MARK: 中間:相機預覽

    private func preview(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ARViewContainer(controller: controller)

            reticle

            if let mid = controller.lineMidpointInView,
               let cm = controller.lengthCM ?? controller.previewLengthCM {
                let isFinal = controller.measure.isComplete
                // 線中點 + 使用者偏移,夾在預覽內(與照片合成同一算式)
                let pos = MeasureAnnotationLayout.displayPosition(
                    midpoint: PlanePoint(x: mid.x, y: mid.y),
                    offsetX: bubbleOffset.width + bubbleDragDelta.width,
                    offsetY: bubbleOffset.height + bubbleDragDelta.height,
                    width: width, height: height, margin: 44)
                // 手勢必須掛在氣泡「本體」上、再做 position——
                // 掛在 position 之後等於掛在整個定位容器,點擊判定會失效(實機驗證過)
                lengthBubble(cm: cm, final: isFinal)
                    .rotationEffect(.degrees(Double(bubbleRotation)))
                    .padding(14)                    // 透明外距,加大觸控範圍
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .updating($bubbleDragDelta) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                bubbleOffset.width += value.translation.width
                                bubbleOffset.height += value.translation.height
                            },
                        including: isFinal ? .all : .none)
                    .position(x: pos.x, y: pos.y)
                    .allowsHitTesting(isFinal)   // 量測完成後才可拖曳
            }

            if flash {
                Color.white.allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onChange(of: controller.measure.isComplete) { _, complete in
            if !complete { bubbleOffset = .zero }   // 重量測時歸位
        }
    }

    private var reticle: some View {
        let ready = controller.reticleHasSurface
        return ZStack {
            Circle()
                .strokeBorder(ready ? Color.green : .white.opacity(0.5), lineWidth: 2)
                .frame(width: 44, height: 44)
            Group {
                Rectangle().frame(width: 1.5, height: 14)
                Rectangle().frame(width: 14, height: 1.5)
            }
            .foregroundStyle(ready ? Color.green : .white.opacity(0.5))
            Circle().fill(ready ? Color.green : .white.opacity(0.5))
                .frame(width: 4, height: 4)
        }
        .allowsHitTesting(false)
    }

    /// 貼在量測線中點的數字氣泡(拍照時同樣式合成進照片)
    private func lengthBubble(cm: Double, final: Bool) -> some View {
        Text(String(format: "%.1f cm", cm))
            .font(.system(size: final ? 20 : 16,
                          weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.black.opacity(0.65), in: Capsule())
            .overlay(Capsule().strokeBorder(
                final ? Color.green.opacity(0.8) : .white.opacity(0.3),
                lineWidth: 1.5))
    }

    // MARK: 下黑帶:復原 / 主按鈕 / 重設

    private var bottomBar: some View {
        HStack {
            circleButton(icon: "arrow.uturn.backward",
                         enabled: !controller.measure.points.isEmpty) {
                controller.undo()
            }
            Spacer()
            mainButton
            Spacer()
            circleButton(icon: "xmark",
                         enabled: !controller.measure.points.isEmpty) {
                controller.reset()
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    /// 唯一主按鈕:「＋」設點 → 兩點齊備變快門(白色實心圓)
    private var mainButton: some View {
        let action = CaptureControls.mainAction(mode: coordinator.flow.mode,
                                                isComplete: controller.measure.isComplete)
        let enabled = CaptureControls.isEnabled(action,
                                                reticleHasSurface: controller.reticleHasSurface)
        return Button {
            switch action {
            case .addPoint:
                controller.addPoint()
            case .shutter:
                withAnimation(.easeOut(duration: 0.1)) { flash = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.easeOut(duration: 0.25)) { flash = false }
                }
                coordinator.takeShot(from: controller,
                                     bubbleOffset: bubbleOffset)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                if action == .shutter {
                    Circle().fill(.white).frame(width: 60, height: 60)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(enabled ? .white : .white.opacity(0.35))
                }
            }
        }
        .disabled(!enabled)
    }

    private func circleButton(icon: String, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.12), in: Circle())
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
        }
        .disabled(!enabled)
    }

    // MARK: 上黑帶小元件

    private var modeToggle: some View {
        Button("連拍") { coordinator.setMode(.burst) }
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
    }

    private var burstBadge: some View {
        HStack(spacing: 8) {
            Text("已拍 \(coordinator.flow.pendingShots) 張")
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
            Button("結束連拍") { coordinator.endBurst() }
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    /// 切換數字方向(90° 循環,記住設定):橫向拍照時把數字轉正
    private var rotateBubbleButton: some View {
        Button {
            bubbleRotation = MeasureAnnotationLayout.nextRotation(bubbleRotation)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rotate.right")
                Text("cm")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .rotationEffect(.degrees(Double(bubbleRotation)))
            }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var recordCountButton: some View {
        Button {
            coordinator.goToStats()
        } label: {
            Text("紀錄 \(records.count)")
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
