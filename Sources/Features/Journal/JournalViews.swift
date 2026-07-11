import SwiftUI
import SwiftData
import MapKit
import Photos

// MARK: - 日誌列表

struct JournalListView: View {
    @Query(sort: \CatchRecord.createdAt, order: .reverse) private var records: [CatchRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("還沒有漁獲紀錄",
                                           systemImage: "fish",
                                           description: Text("到「測量」頁拍下你的第一尾魚!"))
                } else {
                    List(records) { record in
                        NavigationLink(value: record.id) {
                            CatchRow(record: record)
                        }
                        // 左滑管理:刪除 / 編輯(編輯開詳情頁,欄位皆可改)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(record)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                            Button {
                                path.append(record.id)
                            } label: {
                                Label("編輯", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let record = records.first(where: { $0.id == id }) {
                            CatchDetailView(record: record)
                        }
                    }
                }
            }
            .navigationTitle("漁獲日誌")
        }
    }
}

struct CatchRow: View {
    let record: CatchRecord

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(localID: record.photoLocalID)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.lengthLabel)
                    .font(.headline)
                Text(record.createdAt, style: .date)
                    .font(.caption).foregroundStyle(.secondary)
                if let place = record.displayPlace {
                    Label(place, systemImage: "mappin")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 紀錄詳情

struct CatchDetailView: View {
    @Bindable var record: CatchRecord

    var body: some View {
        Form {
            Section {
                // 整組照片(原圖/測量版/比例物版)左右滑動瀏覽
                TabView {
                    ForEach(record.allPhotoIDs, id: \.self) { id in
                        PhotoThumbnail(localID: id,
                                       targetSize: CGSize(width: 800, height: 800))
                            .clipped()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 300)
                .listRowInsets(EdgeInsets())
            }
            Section("測量") {
                LabeledContent("魚長", value: record.lengthLabel)
                LabeledContent("方式", value: record.measureMethod)
                if let method = record.fishingMethod {
                    LabeledContent("漁法", value: method)
                }
                LabeledContent("時間", value: record.createdAt.formatted())
            }
            Section("釣點") {
                if let place = record.displayPlace {
                    LabeledContent("地點", value: place)
                }
                if let lat = record.latitude, let lon = record.longitude {
                    LabeledContent("座標",
                                   value: String(format: "%.4f, %.4f", lat, lon)
                                   + (record.isLocationFuzzed ? "(已模糊化)" : ""))
                }
            }
            Section("魚聲錄音") {
                AudioNoteSection(record: record)
            }
            Section("編輯") {
                PresetOrCustomField(title: "魚種",
                                    options: FormView.speciesOptions,
                                    value: $record.speciesName)
                PresetOrCustomField(title: "漁法",
                                    options: FormView.methodOptions,
                                    value: $record.fishingMethod)
                TextField("實際地點(如:開元港)",
                          text: Binding($record.placeNote, default: ""))
                TextField("備註", text: Binding($record.note, default: ""), axis: .vertical)
            }
        }
        .navigationTitle("漁獲詳情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 魚聲錄音列:錄音/停止/播放/刪除(檔名綁定紀錄 id)
struct AudioNoteSection: View {
    @Bindable var record: CatchRecord
    @StateObject private var audio = AudioNoteRecorder()
    @State private var permissionDenied = false

    private var fileName: String { "audio-\(record.id.uuidString).m4a" }

    var body: some View {
        HStack(spacing: 16) {
            if audio.isRecording {
                Button {
                    audio.stopRecording()
                    record.audioFileName = fileName
                } label: {
                    Label("停止錄音", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    Task {
                        permissionDenied = false
                        if await audio.startRecording(fileName: fileName) == false {
                            permissionDenied = true
                        }
                    }
                } label: {
                    Label(record.audioFileName == nil ? "錄音" : "重錄",
                          systemImage: "mic.fill")
                }
            }

            Spacer()

            if let name = record.audioFileName, !audio.isRecording {
                Button {
                    audio.isPlaying ? audio.stopPlayback() : audio.play(fileName: name)
                } label: {
                    Label(audio.isPlaying ? "停止" : "播放",
                          systemImage: audio.isPlaying ? "stop.fill" : "play.fill")
                }
                Button(role: .destructive) {
                    audio.deleteFile(named: name)
                    record.audioFileName = nil
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .buttonStyle(.borderless)   // Form 列內多按鈕各自獨立觸發

        if audio.isRecording {
            Label("錄音中…再按停止", systemImage: "waveform")
                .font(.caption).foregroundStyle(.red)
        }
        if permissionDenied {
            Text("沒有麥克風權限:請到「設定 > FishMeasureAR」開啟")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

extension Binding where Value == String {
    init(_ source: Binding<String?>, default defaultValue: String) {
        self.init(get: { source.wrappedValue ?? defaultValue },
                  set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

/// 編輯欄位:先列預設選項(點選即套用),最後才是「其他」自行輸入。
/// 目前值命中選項時該選項高亮;輸入自訂文字則自動取消選項高亮。
struct PresetOrCustomField: View {
    let title: String
    let options: [String]
    @Binding var value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    ChipButton(label: option,
                               isSelected: value == option,
                               accent: .cyan) {
                        value = option
                    }
                }
            }
            TextField("其他(自行輸入)", text: customText)
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    /// 自訂輸入:值命中預設選項時顯示空白;輸入即覆寫;
    /// 清空自訂文字回到未選(不誤刪已點選的預設值)。
    private var customText: Binding<String> {
        Binding(
            get: {
                guard let value, !options.contains(value) else { return "" }
                return value
            },
            set: { newText in
                if newText.isEmpty {
                    if let current = value, !options.contains(current) {
                        value = nil
                    }
                } else {
                    value = newText
                }
            })
    }
}

// MARK: - 釣點地圖

struct JournalMapView: View {
    @Query private var records: [CatchRecord]

    private var located: [CatchRecord] {
        records.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        NavigationStack {
            Map {
                ForEach(located) { record in
                    Annotation(record.lengthCM.map { String(format: "%.0fcm", $0) } ?? "未量測",
                               coordinate: CLLocationCoordinate2D(latitude: record.latitude!,
                                                                  longitude: record.longitude!)) {
                        Image(systemName: "fish.fill")
                            .padding(6)
                            .background(.teal, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle("釣點地圖")
        }
    }
}

// MARK: - PhotoKit 縮圖

struct PhotoThumbnail: View {
    let localID: String
    var targetSize = CGSize(width: 200, height: 200)
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "fish").foregroundStyle(.secondary))
            }
        }
        .task(id: localID) {
            // 讀相簿需要讀取授權(與「加入照片」是兩種權限);
            // 未授權就顯示占位圖,不可在無 usage description 下觸發讀取(會被系統終止)
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else { return }

            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
            guard let asset = assets.firstObject else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: targetSize,
                                                  contentMode: .aspectFill,
                                                  options: options) { result, _ in
                if let result { self.image = result }
            }
        }
    }
}
