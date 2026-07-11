import SwiftUI
import SwiftData
import FishMeasureKit

/// 拍完後的資料表單——保持簡潔:
/// 大照片(已含量測線與長度,不重複顯示)+ 魚種快選(必填)+ 漁法一列 + 儲存。
/// 地點/時間自動記錄,只以一行小字帶過。
struct FormView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    @Environment(\.modelContext) private var modelContext

    static let speciesOptions = ["oyod", "rahet", "不食用", "不知道", "不分類", "尚未紀錄"]
    static let methodOptions = ["mamasil", "mamacik", "mapazat", "manaoy", "mongozokozo", "船釣", "射魚"]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                photoHeader(height: geo.size.height * 0.40)

                VStack(alignment: .leading, spacing: 16) {
                    speciesSection
                    methodSection
                    placeNoteSection
                    noteSection
                    autoInfoLine
                    Spacer(minLength: 0)
                    bottomBar
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color(red: 0.055, green: 0.094, blue: 0.133).ignoresSafeArea())
        .overlay {
            if coordinator.isSaving {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("儲存中…")
                            .font(.footnote.bold()).foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(Color.black.opacity(0.75),
                                in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .disabled(coordinator.isSaving)
    }

    // MARK: 照片(scaledToFit;含前一步擺好的參照物疊圖,純顯示)

    private func photoHeader(height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black

                if let shot = coordinator.currentShot {
                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    placedOverlayPreview(shot: shot, container: geo.size)
                }

                Button("‹ 重新量測") { coordinator.backToAdjustFish() }
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)

                // 量魚/比例尺路徑的照片還沒合成標籤,補一個小長度角標;
                // 測距儀路徑照片已含氣泡,不重複顯示
                if let shot = coordinator.currentShot, !shot.labelComposited {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(coordinator.adjustedLengthCM.map {
                                String(format: "%.1f cm", $0)
                            } ?? "未量測")
                                .font(.footnote.bold().monospaced())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.black.opacity(0.65), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .clipped()
    }

    /// 前一步(比例尺編輯)擺放的疊圖,純顯示不可拖
    @ViewBuilder
    private func placedOverlayPreview(shot: MeasureFlowCoordinator.Shot,
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
            Image(uiImage: overlay)
                .resizable()
                .frame(width: overlay.size.width * scale,
                       height: overlay.size.height * scale)
                .rotationEffect(.degrees(coordinator.overlayRotationDegrees))
                .position(ImageFitGeometry.viewPoint(fromImage: center,
                                                     imageSize: imageSize,
                                                     container: container))
                .allowsHitTesting(false)
        }
    }

    // MARK: 魚種(必填)

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("魚種").font(.subheadline.bold()).foregroundStyle(.white)
                if coordinator.flow.speciesValidationFailed {
                    Text("必選").font(.caption).foregroundStyle(.orange)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(Self.speciesOptions, id: \.self) { name in
                    ChipButton(label: name,
                               isSelected: coordinator.flow.selectedSpecies == name,
                               accent: .cyan) {
                        coordinator.selectSpecies(name)
                    }
                }
            }
        }
    }

    // MARK: 漁法(選填,一列橫捲)

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("漁法").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.85))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.methodOptions, id: \.self) { name in
                        ChipButton(label: name,
                                   isSelected: coordinator.flow.selectedMethod == name,
                                   accent: .cyan) {
                            coordinator.selectMethod(name)
                        }
                    }
                }
            }
        }
    }

    // MARK: 地點備註(選填,實際地點如「開元港」)

    private var placeNoteSection: some View {
        TextField("實際地點(選填,如:開元港)", text: $coordinator.placeNote)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 備註(選填)

    private var noteSection: some View {
        TextField("備註(選填)", text: $coordinator.note, axis: .vertical)
            .lineLimit(1...3)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 自動記錄資訊(一行帶過)

    private var autoInfoLine: some View {
        let place = coordinator.currentShot?.placeName
            ?? coordinator.currentShot?.location.map {
                String(format: "%.3f, %.3f",
                       $0.coordinate.latitude, $0.coordinate.longitude)
            }
        let time = (coordinator.currentShot?.capturedAt ?? .now)
            .formatted(date: .numeric, time: .shortened)
        return Label {
            Text("\(place ?? "無定位") · \(time) 已自動記錄")
        } icon: {
            Image(systemName: "mappin.and.ellipse")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
    }

    // MARK: 儲存

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button("儲存＋再拍一尾") {
                Task { await coordinator.saveRecord(to: .captureNext, in: modelContext) }
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(.white)

            Button("儲存") {
                Task { await coordinator.saveRecord(to: .stats, in: modelContext) }
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(.black)
        }
    }
}
