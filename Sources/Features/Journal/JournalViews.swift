import SwiftUI
import SwiftData
import MapKit
import Photos

// MARK: - 日誌列表

struct JournalListView: View {
    @Query(sort: \CatchRecord.createdAt, order: .reverse) private var records: [CatchRecord]

    var body: some View {
        NavigationStack {
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
                if let place = record.placeName {
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
                PhotoThumbnail(localID: record.photoLocalID, targetSize: CGSize(width: 800, height: 800))
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                if let place = record.placeName {
                    LabeledContent("地點", value: place)
                }
                if let lat = record.latitude, let lon = record.longitude {
                    LabeledContent("座標",
                                   value: String(format: "%.4f, %.4f", lat, lon)
                                   + (record.isLocationFuzzed ? "(已模糊化)" : ""))
                }
            }
            Section("備註") {
                TextField("魚種", text: Binding($record.speciesName, default: ""))
                TextField("備註", text: Binding($record.note, default: ""), axis: .vertical)
            }
        }
        .navigationTitle("漁獲詳情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Binding where Value == String {
    init(_ source: Binding<String?>, default defaultValue: String) {
        self.init(get: { source.wrappedValue ?? defaultValue },
                  set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
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
