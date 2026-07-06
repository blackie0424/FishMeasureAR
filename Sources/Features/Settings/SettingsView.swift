import SwiftUI

/// App 設定(UserDefaults)
struct AppSettings {
    @AppStorage("fuzzLocation") var fuzzLocation = false          // 釣點隱私模式
    @AppStorage("embedGPSInPhoto") var embedGPSInPhoto = true     // 照片是否寫入 GPS
    @AppStorage("watermarkEnabled") var watermarkEnabled = true
    @AppStorage("watermarkShowsPlace") var watermarkShowsPlace = true
}

struct SettingsView: View {
    @AppStorage("fuzzLocation") private var fuzzLocation = false
    @AppStorage("embedGPSInPhoto") private var embedGPSInPhoto = true
    @AppStorage("watermarkEnabled") private var watermarkEnabled = true
    @AppStorage("watermarkShowsPlace") private var watermarkShowsPlace = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("釣點隱私模式", isOn: $fuzzLocation)
                    Toggle("照片寫入 GPS 資訊", isOn: $embedGPSInPhoto)
                } header: {
                    Text("隱私")
                } footer: {
                    Text("開啟隱私模式後,座標會模糊化至約 1 公里範圍,保護你的秘密釣點。")
                }

                Section("浮水印") {
                    Toggle("照片浮水印", isOn: $watermarkEnabled)
                    Toggle("浮水印顯示地點", isOn: $watermarkShowsPlace)
                        .disabled(!watermarkEnabled)
                }

                Section("關於") {
                    LabeledContent("版本", value: "0.1.0 (MVP)")
                }
            }
            .navigationTitle("設定")
        }
    }
}
