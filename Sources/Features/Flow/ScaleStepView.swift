import SwiftUI
import FishMeasureKit

/// 步驟 2/2 比例尺:選一個已知尺寸的參照物,把橘色線段兩端
/// 對齊照片中該物品的長邊,即可換算魚長。
struct ScaleStepView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let shot = coordinator.currentShot {
                    let imageSize = shot.image.size
                    let container = geo.size
                    let f1 = ImageFitGeometry.viewPoint(fromImage: shot.fishA,
                                                        imageSize: imageSize, container: container)
                    let f2 = ImageFitGeometry.viewPoint(fromImage: shot.fishB,
                                                        imageSize: imageSize, container: container)
                    let s1 = ImageFitGeometry.viewPoint(fromImage: shot.scaleA,
                                                        imageSize: imageSize, container: container)
                    let s2 = ImageFitGeometry.viewPoint(fromImage: shot.scaleB,
                                                        imageSize: imageSize, container: container)

                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: container.width, height: container.height)

                    // 魚線(唯讀、半透明)
                    Path { p in
                        p.move(to: f1)
                        p.addLine(to: f2)
                    }
                    .stroke(Color.cyan.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: [2, 7], lineCap: .round))
                    .allowsHitTesting(false)

                    if coordinator.selectedReference.lengthCM != nil {
                        Path { p in
                            p.move(to: s1)
                            p.addLine(to: s2)
                        }
                        .stroke(Color.orange,
                                style: StrokeStyle(lineWidth: 3, dash: [6, 4], lineCap: .round))
                        .allowsHitTesting(false)

                        DragHandle(position: s1, color: .orange) { location in
                            coordinator.currentShot?.scaleA = ImageFitGeometry.imagePoint(
                                fromView: location, imageSize: imageSize, container: container)
                        }
                        DragHandle(position: s2, color: .orange) { location in
                            coordinator.currentShot?.scaleB = ImageFitGeometry.imagePoint(
                                fromView: location, imageSize: imageSize, container: container)
                        }
                    }
                }

                VStack {
                    HStack {
                        Button("‹ 上一步") { coordinator.backToAdjustFish() }
                            .font(.footnote)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    }
                    stepBadge
                    lengthReadout
                    Spacer()
                    referencePicker
                    HStack {
                        Spacer()
                        Button {
                            coordinator.advanceFromScale()
                        } label: {
                            Text("完成 ✓")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding()
            }
            .coordinateSpace(name: DragHandle.spaceName)
        }
    }

    private var stepBadge: some View {
        (Text("步驟 2/2  ").bold().foregroundStyle(.orange)
            + Text("選比例尺 · 線段兩端對齊物品長邊").foregroundStyle(.white))
            .font(.footnote)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.black.opacity(0.75), in: Capsule())
    }

    private var lengthReadout: some View {
        Group {
            if let cm = coordinator.adjustedLengthCM {
                VStack(spacing: 2) {
                    Text("魚體長").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%.1f cm", cm))
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Color.black.opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 14))
            } else if coordinator.selectedReference.lengthCM == nil {
                Text("未選比例尺:長度將記錄為「未量測」")
                    .font(.caption)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var referencePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScaleReference.catalog) { ref in
                    ChipButton(label: ref.name,
                               isSelected: coordinator.selectedReference.id == ref.id,
                               accent: .orange) {
                        coordinator.selectedReference = ref
                    }
                }
            }
        }
    }
}
