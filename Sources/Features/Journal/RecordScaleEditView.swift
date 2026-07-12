import SwiftUI
import SwiftData
import Photos
import CoreLocation
import FishMeasureKit
import os

/// 事後替換比例尺物件(不用重拍):
/// 載入該紀錄的「原圖」(全解析度),以紀錄保存的量測端點+長度換算 cm/px
/// (比例正確性的關鍵),選擇/拖曳/旋轉參照物後重新合成「比例物版」照片,
/// 存入相簿並更新紀錄的照片組。
struct RecordScaleEditView: View {
    @Bindable var record: CatchRecord
    @Environment(\.dismiss) private var dismiss

    @State private var originalImage: UIImage?
    /// 拍攝物前景(全幅),蓋在參照物之上
    @State private var subjectCutout: UIImage?
    @State private var reference: ScaleReference?
    @State private var overlayImage: UIImage?
    @State private var center: PlanePoint?
    @State private var rotationDegrees: Double = 0
    @State private var rotationBase: Double = 0
    @State private var isSaving = false
    @State private var errorText: String?

    private static let spaceName = "recordScaleEditSpace"

    /// 這張原圖的 cm/px:紀錄長度 ÷ 保存的端點像素距離
    private var cmPerPixel: Double? {
        guard let length = record.lengthCM,
              let a = record.fishEndpointA,
              let b = record.fishEndpointB else { return nil }
        return PixelScaleMeasurement.cmPerPixel(lengthCM: length,
                                                pointA: a, pointB: b)
    }

    private var overlayLongSidePx: Double? {
        guard let refCM = reference?.lengthCM,
              let cmPerPx = cmPerPixel else { return nil }
        return PixelScaleMeasurement.pixelLength(forCM: refCM,
                                                 cmPerPixel: cmPerPx)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            photoArea
            bottomControls
        }
        .background(Color(red: 0.055, green: 0.094, blue: 0.133).ignoresSafeArea())
        .task { await loadOriginal() }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ProgressView("更新中…").tint(.white).foregroundStyle(.white)
                }
            }
        }
        .disabled(isSaving)
    }

    // MARK: 標題列(返回左上;主要動作在右下,介面統一)

    private var header: some View {
        HStack {
            Button("‹ 取消") { dismiss() }
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text("替換比例尺物件")
                .font(.subheadline.bold()).foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 76, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 照片 + 疊圖(拖曳/旋轉,與拍攝流程同手勢)

    private var photoArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let originalImage {
                    Image(uiImage: originalImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    overlayView(imageSize: originalImage.size, container: geo.size)

                    if let subjectCutout {
                        Image(uiImage: subjectCutout)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .coordinateSpace(name: Self.spaceName)
            .gesture(
                RotateGesture()
                    .onChanged { value in
                        rotationDegrees = rotationBase + value.rotation.degrees
                    }
                    .onEnded { _ in
                        rotationBase = rotationDegrees
                    },
                including: reference == nil ? .none : .all)
        }
        .clipped()
    }

    @ViewBuilder
    private func overlayView(imageSize: CGSize, container: CGSize) -> some View {
        if let overlay = overlayImage,
           let center,
           let longSidePx = overlayLongSidePx {
            let fitRect = ImageFitGeometry.fitRect(imageSize: imageSize,
                                                   in: container)
            let fitScale = imageSize.width > 0 ? fitRect.width / imageSize.width : 0
            let scale = CGFloat(longSidePx) * fitScale
                / max(overlay.size.width, overlay.size.height)
            Image(uiImage: overlay)
                .resizable()
                .frame(width: overlay.size.width * scale,
                       height: overlay.size.height * scale)
                .rotationEffect(.degrees(rotationDegrees))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0,
                                coordinateSpace: .named(Self.spaceName))
                        .onChanged { value in
                            self.center = ImageFitGeometry.imagePoint(
                                fromView: value.location,
                                imageSize: imageSize, container: container)
                        }
                )
                .position(ImageFitGeometry.viewPoint(fromImage: center,
                                                     imageSize: imageSize,
                                                     container: container))
        }
    }

    // MARK: 下方:參照物快選 + 儲存

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.orange)
            } else {
                Text(reference == nil
                     ? "選擇要替換的參照物(依原照片比例等比呈現)"
                     : "單指拖移 · 兩指旋轉,儲存後取代原本的比例物版照片")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 8) {
                ForEach(ScaleReference.overlayCatalog) { ref in
                    ChipButton(label: ref.name,
                               isSelected: reference?.id == ref.id,
                               accent: .orange) {
                        select(ref)
                    }
                }
                Spacer()
                Button {
                    saveReplacement()
                } label: {
                    Text("儲存 ✓")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(reference == nil ? Color.gray : Color.cyan,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                .disabled(reference == nil || isSaving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: 動作

    private func select(_ ref: ScaleReference) {
        reference = ref
        if ref.alignsZeroToSubject,
           let a = record.fishEndpointA, let b = record.fishEndpointB,
           let cmPerPx = cmPerPixel,
           let refCM = ref.lengthCM,
           let boardPx = PixelScaleMeasurement.pixelLength(forCM: refCM,
                                                           cmPerPixel: cmPerPx),
           let placement = OverlayPlacement.boardPlacement(
               fishA: a, fishB: b, boardLengthPx: boardPx, gapPx: 0) {   // 正墊在拍攝物下
            center = placement.center
            rotationDegrees = placement.rotationDegrees
            rotationBase = placement.rotationDegrees
        } else if center == nil, let size = originalImage?.size {
            center = PlanePoint(x: size.width * 0.5, y: size.height * 0.78)
        }
        Task { @MainActor in
            if let name = ref.imageName {
                overlayImage = await ReferenceCutout.load(named: name)
            }
        }
    }

    /// 載入原圖(照片組第 1 張)全解析度
    private func loadOriginal() async {
        guard let firstID = record.allPhotoIDs.first else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            errorText = "沒有相簿權限,無法載入原圖"
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [firstID],
                                         options: nil)
        guard let asset = assets.firstObject else {
            errorText = "找不到原圖(可能已從相簿刪除)"
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options) { result, _ in
            if let result {
                self.originalImage = result
                Task { @MainActor in
                    self.subjectCutout = await SubjectCutout.extract(from: result)
                }
            }
        }
    }

    private func saveReplacement() {
        guard let original = originalImage,
              let overlayImage, let center,
              let longSide = overlayLongSidePx,
              let reference else { return }
        isSaving = true
        Task { @MainActor in
            var composed = ImageAnnotator.drawOverlay(
                overlayImage,
                centeredAt: CGPoint(x: center.x, y: center.y),
                longSidePx: longSide,
                rotationDegrees: rotationDegrees,
                on: original)
            if let subjectCutout {
                composed = ImageAnnotator.drawSubjectOnTop(subjectCutout,
                                                           on: composed)
            }

            let settings = AppSettings()
            let gps: CLLocation? = {
                guard settings.embedGPSInPhoto,
                      let lat = record.latitude,
                      let lon = record.longitude else { return nil }
                return CLLocation(latitude: lat, longitude: lon)   // 已含隱私處理
            }()
            let options = PhotoSaveOptions(
                watermarkEnabled: settings.watermarkEnabled,
                watermarkPlace: settings.watermarkShowsPlace ? record.displayPlace : nil,
                gpsLocation: gps)

            do {
                let newID = try await CaptureService()
                    .saveSingle(image: composed, options: options)
                record.photoLocalIDs = PhotoSetLayout.replacingReferencePhoto(
                    in: record.photoLocalIDs, with: newID)
                record.referenceObjectsUsed = [reference.id]
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorText = "儲存失敗:\(error.localizedDescription)"
            }
        }
    }
}
