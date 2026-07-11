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
    /// 量測流程與今日調查共用同一個 coordinator(連拍佇列/狀態一致)
    @StateObject private var coordinator = MeasureFlowCoordinator()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MeasureFlowScreen(coordinator: coordinator)
                .tabItem { Label("測量", systemImage: "ruler") }
                .tag(0)

            StatsView(coordinator: coordinator,
                      onNavigateToMeasure: { selectedTab = 0 })
                .tabItem { Label("今日調查", systemImage: "chart.bar.doc.horizontal") }
                .tag(1)

            JournalListView()
                .tabItem { Label("漁獲日誌", systemImage: "book.closed") }
                .tag(2)

            JournalMapView()
                .tabItem { Label("釣點地圖", systemImage: "map") }
                .tag(3)

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(4)
        }
        // 流程導向統計(儲存離線/結束連拍)→ 切到「今日調查」分頁,
        // 測量分頁回到相機——「按下測量就直接進入照相模式」
        .onChange(of: coordinator.flow.screen) { _, screen in
            if screen == .stats {
                selectedTab = 1
                coordinator.backToCapture()
            }
        }
    }
}
