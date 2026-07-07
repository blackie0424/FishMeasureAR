import SwiftUI
import SwiftData
import RealityKit
import FishMeasureKit

// MARK: - ARView 包裝

struct ARViewContainer: UIViewRepresentable {
    let controller: MeasureSessionController

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.renderOptions.insert(.disableMotionBlur)
        controller.start(on: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - 拍照畫面(工作流入口,AR 即時測量疊加)

struct CaptureView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    @StateObject private var controller = MeasureSessionController()
    @AppStorage("showGrid") private var showGrid = true
    @State private var flash = false
    @State private var gpsLabel: String?
    @Query private var records: [CatchRecord]

    var body: some View {
        ZStack {
            ARViewContainer(controller: controller)
                .ignoresSafeArea()

            if let (v1, v2) = controller.endpointsInView {
                MeasureLineOverlay(p1: v1, p2: v2,
                                   isStable: controller.status == .stable)
            }
            if showGrid { GridOverlay() }

            VStack(spacing: 10) {
                hintBadge
                HStack {
                    modeChips
                    Spacer()
                    ChipButton(label: "格線", isSelected: showGrid) {
                        showGrid.toggle()
                    }
                }
                Spacer()
                lengthDisplay
                if coordinator.flow.mode == .burst { burstBar }
                shutterButton
                HStack {
                    gpsBadge
                    Spacer()
                    recordCountButton
                }
            }
            .padding()

            if flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .onAppear { coordinator.locationService.requestAuthorization() }
        .task {
            let location = await coordinator.locationService.currentLocation()
            let place = await coordinator.locationService.reverseGeocode(location)
            if let c = location?.coordinate {
                gpsLabel = String(format: "%.3f, %.3f", c.latitude, c.longitude)
                    + (place.map { " · \($0)" } ?? "")
            }
        }
    }

    // MARK: 子元件

    private var hintBadge: some View {
        let (text, color): (String, Color) = switch controller.status {
        case .searching:   ("魚與比例尺並排橫放 · 垂直俯拍", .yellow)
        case .measuring:   ("測量中…請保持穩定", .yellow)
        case .stable:      ("已穩定,可拍攝", .green)
        case .badDistance: ("距離不當,請保持 30–60cm 垂直俯拍", .red)
        }
        return Text(text)
            .font(.footnote.bold())
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color.opacity(0.85), in: Capsule())
            .foregroundStyle(.black)
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            ChipButton(label: "單拍",
                       isSelected: coordinator.flow.mode == .single) {
                coordinator.setMode(.single)
            }
            ChipButton(label: "連拍(稍後量)",
                       isSelected: coordinator.flow.mode == .burst,
                       accent: .orange) {
                coordinator.setMode(.burst)
            }
        }
    }

    private var lengthDisplay: some View {
        Group {
            if let cm = controller.lengthCM {
                Text(String(format: "%.1f cm", cm))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                if !controller.hasLiDAR {
                    Text("估計值(此機型無 LiDAR)")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

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

    private var shutterButton: some View {
        Button {
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
                .background(Circle().fill(
                    controller.status == .stable ? .white : .white.opacity(0.4)))
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

// MARK: - 測量線疊加

struct MeasureLineOverlay: View {
    let p1: CGPoint
    let p2: CGPoint
    let isStable: Bool

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path,
                           with: .color(isStable ? .green : .yellow),
                           style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
            for p in [p1, p2] {
                let dot = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
                context.fill(dot, with: .color(.white))
                context.stroke(dot, with: .color(isStable ? .green : .yellow),
                               style: StrokeStyle(lineWidth: 3))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
