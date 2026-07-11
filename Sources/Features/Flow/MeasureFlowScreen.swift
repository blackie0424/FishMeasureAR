import SwiftUI
import FishMeasureKit

/// 測量工作流根視圖:依狀態機切換五個畫面(拍照/量魚/比例尺/表單/統計)。
struct MeasureFlowScreen: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator

    var body: some View {
        // NavigationStack 只為了 toolbar 可見性控制:
        // 拍攝畫面顯示分頁列(可隨時切到其他分頁);
        // 進入流程(確認線/比例尺/表單)後隱藏,避免中途誤觸離開。
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(coordinator.flow.screen == .capture ? .visible : .hidden,
                         for: .tabBar)
        }
    }

    private var content: some View {
        ZStack {
            switch coordinator.flow.screen {
            case .capture:
                CaptureView(coordinator: coordinator)
            case .adjustFish:
                AdjustFishView(coordinator: coordinator)
            case .scale:
                ScaleStepView(coordinator: coordinator)
            case .overlayEdit:
                OverlayEditView(coordinator: coordinator)
            case .form:
                FormView(coordinator: coordinator)
            case .stats:
                StatsView(coordinator: coordinator)
            }

            if let toast = coordinator.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.bold())
                        .padding(.horizontal, 20).padding(.vertical, 9)
                        .background(Color.green.opacity(0.95), in: Capsule())
                        .foregroundStyle(.black)
                        .padding(.bottom, 70)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: coordinator.toast)
    }
}

// MARK: - 共用元件

/// 膠囊快選鈕(模式/比例尺/魚種/漁法)
struct ChipButton: View {
    let label: String
    let isSelected: Bool
    var accent: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(isSelected ? .bold : .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? accent.opacity(0.92) : Color.black.opacity(0.55),
                            in: Capsule())
                .foregroundStyle(isSelected ? .black : .white)
                .overlay(Capsule().strokeBorder(
                    isSelected ? accent : .white.opacity(0.25), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// 顯示影像於容器內(scaledToFit)時的實際繪製區域,
/// 供「影像像素座標 ↔ view 座標」互換。
enum ImageFitGeometry {
    static func fitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale,
                          height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func viewPoint(fromImage p: PlanePoint,
                          imageSize: CGSize, container: CGSize) -> CGPoint {
        let rect = fitRect(imageSize: imageSize, in: container)
        guard imageSize.width > 0 else { return .zero }
        let scale = rect.width / imageSize.width
        return CGPoint(x: rect.minX + p.x * scale, y: rect.minY + p.y * scale)
    }

    static func imagePoint(fromView p: CGPoint,
                           imageSize: CGSize, container: CGSize) -> PlanePoint {
        let rect = fitRect(imageSize: imageSize, in: container)
        guard rect.width > 0 else { return PlanePoint(x: 0, y: 0) }
        let scale = imageSize.width / rect.width
        let x = (Double(p.x) - rect.minX) * scale
        let y = (Double(p.y) - rect.minY) * scale
        return PlanePoint(x: min(max(x, 0), imageSize.width),
                          y: min(max(y, 0), imageSize.height))
    }
}

/// 可拖曳端點(白心圓 + 色框),供量魚線與比例尺線共用。
/// 容器 ZStack 需標記 `.coordinateSpace(name: DragHandle.spaceName)`,
/// 拖曳座標才會以照片容器為基準。
struct DragHandle: View {
    static let spaceName = "photoSpace"

    let position: CGPoint
    let color: Color
    let onDrag: (CGPoint) -> Void

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(color, lineWidth: 4).frame(width: 26, height: 26))
            .frame(width: 44, height: 44)   // 好按的觸控範圍
            .contentShape(Circle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0,
                            coordinateSpace: .named(Self.spaceName))
                    .onChanged { onDrag($0.location) }
            )
    }
}
