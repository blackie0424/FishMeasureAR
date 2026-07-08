import SwiftUI
import SwiftData
import RealityKit
import FishMeasureKit

// MARK: - ARView 包裝

struct ARViewContainer: UIViewRepresentable {
    let controller: TapMeasureSessionController

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.renderOptions.insert(.disableMotionBlur)
        controller.start(on: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - 拍照畫面
// 版面:上下黑帶放所有控制項,中間 3:4 相機預覽保持乾淨;
// 預覽區只有準星、貼在量測線上的數字氣泡。
// 操作:唯一主按鈕依情境切換——「＋」設 A、B 點 → 兩點齊備變快門。

struct CaptureView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    @StateObject private var controller = TapMeasureSessionController()
    @State private var flash = false
    @Query private var records: [CatchRecord]

    var body: some View {
        // 尺寸一律明確計算:aspectRatio 對 UIViewRepresentable 會採用
        // ARView 的 intrinsic 尺寸,導致預覽縮成一小塊(實機截圖確認過),
        // 這裡直接用 GeometryReader 指定預覽框大小。
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                preview
                    .frame(width: geo.size.width,
                           height: previewHeight(in: geo.size))
                    .clipped()
                bottomBar
                    .frame(maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height,
                   alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { coordinator.locationService.requestAuthorization() }
        .onDisappear { controller.pause() }
    }

    /// 預覽高度:盡量吃滿寬度下的 4:3(相機原生比例),
    /// 但保留上下控制帶最小空間;剩餘黑帶自然落在上下兩端。
    private func previewHeight(in size: CGSize) -> CGFloat {
        let reservedForBars: CGFloat = 200
        return min(size.width * 4.0 / 3.0,
                   max(size.height - reservedForBars, 240))
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
        default: return "量測完成,按快門拍照"
        }
    }

    private var hintColor: Color {
        controller.measure.isComplete ? .green : .yellow
    }

    // MARK: 中間:相機預覽(3:4)

    private var preview: some View {
        ZStack {
            ARViewContainer(controller: controller)

            reticle

            if let mid = controller.lineMidpointInView,
               let cm = controller.lengthCM ?? controller.previewLengthCM {
                lengthBubble(cm: cm, final: controller.measure.isComplete)
                    .position(mid)
                    .allowsHitTesting(false)
            }

            if flash {
                Color.white.allowsHitTesting(false)
            }
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
                coordinator.takeShot(from: controller)
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
