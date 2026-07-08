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

// MARK: - 拍照畫面(仿 iOS 測距儀:準星 + ＋ 設點)

struct CaptureView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    @StateObject private var controller = TapMeasureSessionController()
    @State private var flash = false
    @State private var gpsLabel: String?
    @Query private var records: [CatchRecord]

    var body: some View {
        ZStack {
            ARViewContainer(controller: controller)
                .ignoresSafeArea()

            reticle

            VStack {
                hintBadge
                if coordinator.flow.mode == .burst { burstBar.padding(.top, 6) }
                Spacer()
                lengthBadge
                controlBar
                HStack {
                    gpsBadge
                    Spacer()
                    modeToggle
                    recordCountButton
                }
            }
            .padding()

            if flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .onAppear { coordinator.locationService.requestAuthorization() }
        .onDisappear { controller.pause() }
        .task {
            let location = await coordinator.locationService.currentLocation()
            let place = await coordinator.locationService.reverseGeocode(location)
            if let c = location?.coordinate {
                gpsLabel = String(format: "%.3f, %.3f", c.latitude, c.longitude)
                    + (place.map { " · \($0)" } ?? "")
            }
        }
    }

    // MARK: 準星(僅螢幕顯示,不入快照)

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

    // MARK: 提示與讀值

    private var hintBadge: some View {
        let (text, color): (String, Color) = {
            if !controller.reticleHasSurface && controller.measure.points.isEmpty {
                return ("緩慢移動手機以偵測表面", .yellow)
            }
            switch controller.measure.points.count {
            case 0:  return ("準星對準魚的吻端,按「＋」設定 A 點", .yellow)
            case 1:  return ("移到尾叉,按「＋」設定 B 點", .yellow)
            default: return ("量測完成,可拍攝;要重量按「重設」", .green)
            }
        }()
        return Text(text)
            .font(.footnote.bold())
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(color.opacity(0.88), in: Capsule())
            .foregroundStyle(.black)
    }

    private var lengthBadge: some View {
        Group {
            if let cm = controller.lengthCM {
                Text(String(format: "%.1f cm", cm))
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            } else if let cm = controller.previewLengthCM {
                Text(String(format: "%.1f cm", cm))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(radius: 3)
            }
            if controller.lengthCM != nil, !controller.hasLiDAR {
                Text("估計值(此機型無 LiDAR)")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: 操作列:復原 / ＋ / 快門 / 重設

    private var controlBar: some View {
        HStack(spacing: 26) {
            circleButton(icon: "arrow.uturn.backward",
                         enabled: !controller.measure.points.isEmpty) {
                controller.undo()
            }

            addPointButton

            shutterButton

            circleButton(icon: "xmark",
                         enabled: !controller.measure.points.isEmpty) {
                controller.reset()
            }
        }
        .padding(.vertical, 8)
    }

    private var addPointButton: some View {
        let enabled = controller.reticleHasSurface && controller.measure.canAddPoint
        return Button {
            controller.addPoint()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .frame(width: 62, height: 62)
                .background(enabled ? Color.white : .white.opacity(0.25),
                            in: Circle())
                .foregroundStyle(enabled ? .black : .white.opacity(0.5))
        }
        .disabled(!enabled)
    }

    private var shutterButton: some View {
        let ready = controller.measure.isComplete || coordinator.flow.mode == .burst
        return Button {
            withAnimation(.easeOut(duration: 0.1)) { flash = true }
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.25)) { flash = false }
            }
            coordinator.takeShot(from: controller)
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 5)
                .frame(width: 74, height: 74)
                .background(Circle().fill(ready ? .white : .white.opacity(0.4)))
        }
    }

    private func circleButton(icon: String, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(Color.black.opacity(0.55), in: Circle())
                .foregroundStyle(enabled ? .white : .white.opacity(0.3))
        }
        .disabled(!enabled)
    }

    // MARK: 底列

    private var burstBar: some View {
        HStack(spacing: 10) {
            Text("已拍 \(coordinator.flow.pendingShots) 張 · 稍後量測")
                .font(.footnote.bold())
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.orange.opacity(0.92), in: Capsule())
                .foregroundStyle(.black)
            Button("結束連拍") { coordinator.endBurst() }
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.black.opacity(0.7), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                .foregroundStyle(.white)
        }
    }

    private var modeToggle: some View {
        ChipButton(label: coordinator.flow.mode == .burst ? "連拍中" : "連拍",
                   isSelected: coordinator.flow.mode == .burst,
                   accent: .orange) {
            coordinator.setMode(coordinator.flow.mode == .burst ? .single : .burst)
        }
    }

    private var gpsBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(gpsLabel == nil ? .yellow : .green)
                .frame(width: 8, height: 8)
            Text(gpsLabel ?? "定位中…")
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white.opacity(0.85))
    }

    private var recordCountButton: some View {
        Button {
            coordinator.goToStats()
        } label: {
            Text("紀錄 \(records.count)")
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

