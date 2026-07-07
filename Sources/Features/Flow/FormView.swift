import SwiftUI
import SwiftData
import FishMeasureKit

/// 資料表單:魚種(必填)、漁法快選,地點/時間自動帶入。
struct FormView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    @Environment(\.modelContext) private var modelContext

    static let speciesOptions = ["吳郭魚", "白帶魚", "午仔", "花身仔", "黑鯛", "臭肚", "其他"]
    static let methodOptions = ["岸釣", "船釣", "磯釣", "刺網", "一支釣"]

    private let chipColumns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            photoHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("魚種 *") {
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                            ForEach(Self.speciesOptions, id: \.self) { name in
                                ChipButton(label: name,
                                           isSelected: coordinator.flow.selectedSpecies == name,
                                           accent: .cyan) {
                                    coordinator.selectSpecies(name)
                                }
                            }
                        }
                    }
                    section("釣法/漁法") {
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                            ForEach(Self.methodOptions, id: \.self) { name in
                                ChipButton(label: name,
                                           isSelected: coordinator.flow.selectedMethod == name,
                                           accent: .cyan) {
                                    coordinator.selectMethod(name)
                                }
                            }
                        }
                    }
                    autoFields
                }
                .padding()
            }
            bottomBar
        }
        .background(Color(red: 0.055, green: 0.094, blue: 0.133).ignoresSafeArea())
    }

    // MARK: 子元件

    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let shot = coordinator.currentShot {
                Image(uiImage: shot.image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.adjustedLengthCM.map {
                    String(format: "%.1f cm", $0)
                } ?? "未量測")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text(scaleCaption)
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)

            VStack {
                HStack {
                    Button("‹ 重新量測") { coordinator.backToAdjustFish() }
                        .font(.caption)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(height: 180)
    }

    private var scaleCaption: String {
        if coordinator.hasMetricLength {
            return "AR 自動測量"
        }
        if let cm = coordinator.selectedReference.lengthCM {
            return "比例尺:\(coordinator.selectedReference.name)(\(String(format: "%.1f", cm)) cm)"
        }
        return "無比例尺(未換算長度)"
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption).foregroundStyle(.cyan.opacity(0.7))
                .kerning(1.5)
            content()
        }
    }

    private var autoFields: some View {
        HStack(spacing: 10) {
            autoField("地點(自動)",
                      coordinator.currentShot?.placeName
                        ?? coordinator.currentShot?.location.map {
                            String(format: "%.3f, %.3f",
                                   $0.coordinate.latitude, $0.coordinate.longitude)
                        }
                        ?? "無定位")
            autoField("時間(自動)",
                      (coordinator.currentShot?.capturedAt ?? .now)
                          .formatted(date: .numeric, time: .shortened))
        }
    }

    private func autoField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.cyan.opacity(0.6))
            Text(value).font(.footnote.monospaced()).foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white.opacity(0.09), lineWidth: 1))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if coordinator.flow.speciesValidationFailed {
                Text("請先選擇魚種")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button("儲存＋再拍一尾") {
                Task { await coordinator.saveRecord(to: .captureNext, in: modelContext) }
            }
            .font(.footnote.bold())
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)

            Button("儲存(離線)") {
                Task { await coordinator.saveRecord(to: .stats, in: modelContext) }
            }
            .font(.footnote.bold())
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.black)
        }
        .padding()
    }
}
