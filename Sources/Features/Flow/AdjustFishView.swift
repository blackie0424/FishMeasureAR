import SwiftUI
import FishMeasureKit

/// 確認測量線:照片已凍結,拖曳兩端點對齊物體(吻端 → 尾叉)。
/// AR 錨點在改構圖時可能飄移——凍結後修正才可靠。
/// AR 已測得長度時端點預填、拖曳按 cm/px 重算;無讀值則進比例尺步驟。
struct AdjustFishView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let shot = coordinator.currentShot {
                    let imageSize = shot.image.size
                    let container = geo.size
                    let v1 = ImageFitGeometry.viewPoint(fromImage: shot.fishA,
                                                        imageSize: imageSize,
                                                        container: container)
                    let v2 = ImageFitGeometry.viewPoint(fromImage: shot.fishB,
                                                        imageSize: imageSize,
                                                        container: container)

                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: container.width, height: container.height)

                    Path { p in
                        p.move(to: v1)
                        p.addLine(to: v2)
                    }
                    .stroke(Color.cyan,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
                    .allowsHitTesting(false)

                    DragHandle(position: v1, color: .cyan) { location in
                        coordinator.currentShot?.fishA = ImageFitGeometry.imagePoint(
                            fromView: location, imageSize: imageSize, container: container)
                    }
                    DragHandle(position: v2, color: .cyan) { location in
                        coordinator.currentShot?.fishB = ImageFitGeometry.imagePoint(
                            fromView: location, imageSize: imageSize, container: container)
                    }
                }

                VStack {
                    HStack {
                        Button("‹ 重拍") { coordinator.backToCapture() }
                            .font(.footnote)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    }
                    stepBadge
                    if let cm = coordinator.adjustedLengthCM {
                        Text(String(format: "%.1f cm", cm))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(.cyan)
                            .shadow(radius: 4)
                    }
                    Spacer()
                    HStack {
                        Text("拖曳兩個端點對齊魚身")
                            .font(.caption)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Button {
                            coordinator.advanceFromAdjustFish()
                        } label: {
                            Text("下一步 ›")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
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
        (Text("確認測量線  ").bold().foregroundStyle(.cyan)
            + Text("線若偏移,拖曳端點對齊物體").foregroundStyle(.white))
            .font(.footnote)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.black.opacity(0.75), in: Capsule())
    }
}
