import SwiftUI
import FishMeasureKit

/// 比例尺編輯(獨立步驟):拍照量測完成後,先在大畫面上
/// 選擇參照物(去背圖依實際 cm/px 等比縮放)、拖曳擺放,
/// 完成後才進資料填寫。不需要參照物可直接下一步。
struct OverlayEditView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    /// 兩指旋轉的基準角(手勢結束時累積)
    @State private var rotationBase: Double = 0

    private static let photoSpaceName = "overlayEditPhotoSpace"

    var body: some View {
        VStack(spacing: 0) {
            header
            photoArea
            bottomControls
        }
        .background(Color(red: 0.055, green: 0.094, blue: 0.133).ignoresSafeArea())
    }

    // MARK: 標題列

    // 介面統一:返回在左上、主要動作(下一步)在右下,與確認頁/比例尺換算頁一致
    private var header: some View {
        HStack {
            Button("‹ 上一步") { coordinator.backFromOverlayEdit() }
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text("比例尺物件")
                .font(.subheadline.bold()).foregroundStyle(.white)
            Spacer()
            // 佔位保持標題置中
            Color.clear.frame(width: 76, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 大照片 + 疊圖拖曳

    private var photoArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let shot = coordinator.currentShot {
                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    referenceOverlay(shot: shot, container: geo.size)
                }
            }
            .coordinateSpace(name: Self.photoSpaceName)
            // 兩指旋轉掛在整個照片區:單指拖(疊圖本體)移動、雙指在照片上
            // 任意位置旋轉,兩種手勢互不干擾
            .gesture(
                RotateGesture()
                    .onChanged { value in
                        coordinator.overlayRotationDegrees =
                            rotationBase + value.rotation.degrees
                    }
                    .onEnded { _ in
                        rotationBase = coordinator.overlayRotationDegrees
                    },
                including: coordinator.overlayReference == nil ? .none : .all)
        }
        .clipped()
    }

    /// 參照物疊圖:按實際 cm/px 等比,拖曳擺放(存檔同位置合成)。
    /// 手勢掛本體+named space(教訓:掛在 .position 之後收不到觸控)。
    @ViewBuilder
    private func referenceOverlay(shot: MeasureFlowCoordinator.Shot,
                                  container: CGSize) -> some View {
        if let overlay = coordinator.overlayImage,
           let center = coordinator.overlayCenter,
           let longSidePx = coordinator.overlayLongSidePx {
            let imageSize = shot.image.size
            let fitRect = ImageFitGeometry.fitRect(imageSize: imageSize,
                                                   in: container)
            let fitScale = imageSize.width > 0 ? fitRect.width / imageSize.width : 0
            let scale = CGFloat(longSidePx) * fitScale
                / max(overlay.size.width, overlay.size.height)
            let viewPos = ImageFitGeometry.viewPoint(fromImage: center,
                                                     imageSize: imageSize,
                                                     container: container)
            Image(uiImage: overlay)
                .resizable()
                .frame(width: overlay.size.width * scale,
                       height: overlay.size.height * scale)
                .rotationEffect(.degrees(coordinator.overlayRotationDegrees))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0,
                                coordinateSpace: .named(Self.photoSpaceName))
                        .onChanged { value in
                            coordinator.overlayCenter = ImageFitGeometry.imagePoint(
                                fromView: value.location,
                                imageSize: imageSize, container: container)
                        }
                )
                .position(viewPos)
        }
    }

    // MARK: 下方:參照物快選 + 提示

    private var bottomControls: some View {
        VStack(spacing: 10) {
            Text(coordinator.overlayReference == nil
                 ? "選擇參照物放進照片(依實際尺寸等比);不需要可直接下一步"
                 : "單指拖移 · 兩指旋轉(或按 ↻ 轉 90°),存檔時合成在同位置")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 8) {
                ChipButton(label: "無",
                           isSelected: coordinator.overlayReference == nil,
                           accent: .orange) {
                    coordinator.selectOverlay(nil)
                    rotationBase = coordinator.overlayRotationDegrees
                }
                ForEach(ScaleReference.overlayCatalog) { ref in
                    ChipButton(label: ref.name,
                               isSelected: coordinator.overlayReference?.id == ref.id,
                               accent: .orange) {
                        coordinator.selectOverlay(ref)
                        rotationBase = coordinator.overlayRotationDegrees
                    }
                }
                if coordinator.overlayReference != nil {
                    Button {
                        let next = MeasureAnnotationLayout.nextRotation(
                            Int(coordinator.overlayRotationDegrees.rounded()))
                        coordinator.overlayRotationDegrees = Double(next)
                        rotationBase = Double(next)
                    } label: {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(9)
                            .background(Color.white.opacity(0.12), in: Circle())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Button {
                    coordinator.advanceFromOverlayEdit()
                } label: {
                    Text("下一步 ›")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}
