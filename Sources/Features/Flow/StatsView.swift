import SwiftUI
import SwiftData
import FishMeasureKit

/// 今日調查:種類長條、尺寸分布、紀錄清單、CSV 匯出、連拍待量佇列。
struct StatsView: View {
    @ObservedObject var coordinator: MeasureFlowCoordinator
    /// 由 RootView 注入:切回「測量」分頁(繼續測量/去量用)
    var onNavigateToMeasure: (() -> Void)? = nil
    @Query(sort: \CatchRecord.createdAt, order: .reverse)
    private var allRecords: [CatchRecord]
    @State private var shareURL: URL?

    private var todayRecords: [CatchRecord] {
        let start = Calendar.current.startOfDay(for: .now)
        return allRecords.filter { $0.createdAt >= start }
    }

    private var entries: [CatchEntry] {
        todayRecords.map {
            CatchEntry(species: $0.speciesName ?? "未分類",
                       lengthCM: $0.lengthCM,
                       method: $0.fishingMethod,
                       capturedAt: $0.createdAt,
                       latitude: $0.latitude, longitude: $0.longitude,
                       placeName: $0.placeName,
                       isSynced: $0.isSynced)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            HStack(spacing: 10) {
                speciesPanel
                sizePanel
            }
            recordList
            bottomBar
        }
        .padding()
        .background(Color(red: 0.055, green: 0.094, blue: 0.133).ignoresSafeArea())
        .sheet(isPresented: Binding(get: { shareURL != nil },
                                    set: { if !$0 { shareURL = nil } })) {
            if let shareURL {
                ActivityShareSheet(items: [shareURL])
            }
        }
    }

    // MARK: 子區塊

    private var header: some View {
        HStack(spacing: 10) {
            Text("今日調查").font(.headline.bold())
            Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if coordinator.flow.pendingShots > 0 {
                Button("未量測 ×\(coordinator.flow.pendingShots) ▸ 去量") {
                    coordinator.beginPendingMeasurement()
                    onNavigateToMeasure?()
                }
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(.orange, lineWidth: 1.5))
                .foregroundStyle(.orange)
            }
            Text("✓ 已存 \(todayRecords.count) · ⟳ 待傳 \(CatchStatistics.unsyncedCount(of: entries))")
                .font(.caption2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.green.opacity(0.12), in: Capsule())
                .foregroundStyle(.green)
        }
        .foregroundStyle(.white)
    }

    private var speciesPanel: some View {
        let bars = CatchStatistics.speciesBars(from: entries)
        return panel("種類(\(bars.count))") {
            VStack(spacing: 5) {
                if bars.isEmpty {
                    Text("尚無紀錄").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(bars, id: \.name) { bar in
                    HStack(spacing: 8) {
                        Text(bar.name)
                            .font(.caption2).foregroundStyle(.white.opacity(0.85))
                            .frame(width: 48, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.cyan)
                                .frame(width: max(geo.size.width * bar.fraction, 4))
                        }
                        .frame(height: 8)
                        Text("\(bar.count)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sizePanel: some View {
        let bins = CatchStatistics.sizeBins(from: entries)
        return panel("尺寸分布(cm)") {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(bins, id: \.label) { bin in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(height: max(52 * bin.fraction, 2))
                        Text(bin.label)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func panel<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(.cyan.opacity(0.7)).kerning(1)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var recordList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if todayRecords.isEmpty {
                    Text("今天還沒有紀錄,點「繼續測量」開始")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
                ForEach(todayRecords) { record in
                    HStack(spacing: 12) {
                        PhotoThumbnail(localID: record.photoLocalID)
                            .frame(width: 40, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(record.speciesName ?? "未分類")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 64, alignment: .leading)
                        Text(record.lengthLabel)
                            .font(.caption.monospaced()).foregroundStyle(.cyan)
                            .frame(width: 70, alignment: .leading)
                        Text(record.fishingMethod ?? "—")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Text(record.isSynced ? "✓ 已同步" : "⟳ 待傳")
                            .font(.system(size: 10))
                            .foregroundStyle(record.isSynced ? .green : .orange)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider().overlay(.white.opacity(0.05))
                }
            }
        }
        .background(Color.white.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("匯出 CSV") { exportCSV() }
                .font(.footnote)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
                .foregroundStyle(.white)
                .disabled(todayRecords.isEmpty)

            Button("📷 繼續測量") {
                coordinator.backToCapture()
                onNavigateToMeasure?()
            }
                .font(.footnote.bold())
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
        }
    }

    private func exportCSV() {
        let csv = CSVExporter.export(entries)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(CSVExporter.filename(for: .now))
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
        } catch {
            coordinator.showToast("匯出失敗:\(error.localizedDescription)")
        }
    }
}

/// UIActivityViewController 包裝(分享 CSV 檔)
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {}
}
