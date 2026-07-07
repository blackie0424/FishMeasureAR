import SwiftUI
import SwiftData

@main
struct FishMeasureARApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: CatchRecord.self)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            MeasureFlowScreen()
                .tabItem { Label("測量", systemImage: "ruler") }

            JournalListView()
                .tabItem { Label("漁獲日誌", systemImage: "book.closed") }

            JournalMapView()
                .tabItem { Label("釣點地圖", systemImage: "map") }

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
