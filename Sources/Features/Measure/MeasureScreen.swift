import SwiftUI
import RealityKit
import SwiftData

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

// MARK: - 測量主畫面

struct MeasureScreen: View {
    @StateObject private var controller = MeasureSessionController()
    @State private var placer = ReferenceObjectPlacer()
    @State private var showSaved = false
    @Environment(\.modelContext) private var modelContext

    private let captureService = CaptureService()
    private let locationService = LocationService()

    var body: some View {
        ZStack {
            ARViewContainer(controller: controller)
                .ignoresSafeArea()

            // 測量線疊加
            if let (v1, v2) = controller.endpointsInView {
                MeasureLineOverlay(p1: v1, p2: v2, isStable: controller.status == .stable)
            }

            VStack {
                statusBadge
                Spacer()
                lengthDisplay
                referencePicker
                shutterButton
                    .padding(.bottom, 8)
            }
            .padding()
        }
        .onAppear { locationService.requestAuthorization() }
        .alert("已儲存到漁獲日誌", isPresented: $showSaved) {
            Button("好") {}
        }
    }

    // MARK: 子元件

    private var statusBadge: some View {
        let (text, color): (String, Color) = switch controller.status {
        case .searching:   ("尋找魚體中…請將魚平放並俯拍", .yellow)
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

    private var referencePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ReferenceObject.catalog) { obj in
                    Button {
                        if let arView = controller.arView {
                            placer.place(obj, near: controller.worldEndpoints, in: arView)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: obj.icon).font(.title2)
                            Text(obj.name).font(.caption2)
                        }
                        .frame(width: 72, height: 64)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(.white)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var shutterButton: some View {
        Button {
            Task { await capture() }
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 5)
                .frame(width: 74, height: 74)
                .background(Circle().fill(controller.status == .stable ? .white : .white.opacity(0.4)))
        }
        .disabled(controller.lengthCM == nil)
    }

    // MARK: 拍攝流程

    private func capture() async {
        guard let arView = controller.arView,
              let lengthCM = controller.lengthCM else { return }

        let location = await locationService.currentLocation()
        let placeName = await locationService.reverseGeocode(location)

        do {
            let localID = try await captureService.captureAndSave(
                arView: arView,
                lengthCM: lengthCM,
                location: location,
                placeName: placeName)

            let record = CatchRecord(
                lengthCM: lengthCM,
                measureMethod: controller.hasLiDAR ? "auto-lidar" : "auto-plane",
                location: location,
                placeName: placeName,
                photoLocalID: localID,
                referenceObjectsUsed: placer.placedIDs)
            modelContext.insert(record)
            showSaved = true
        } catch {
            print("Capture failed: \(error)")
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
