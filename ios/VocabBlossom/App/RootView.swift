import SwiftUI

/// 下部タブ + セッションのフルスクリーンモーダル、という画面構造。ホームがグループの入口を兼ねる
struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if settings.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: settings.hasOnboarded)
    }
}

struct MainTabView: View {
    enum TabId: String {
        case home, stats, settings
    }

    @State private var selection: TabId = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("ホーム", systemImage: "house.fill", value: TabId.home) {
                HomeView()
            }
            Tab("統計", systemImage: "chart.bar.fill", value: TabId.stats) {
                StatsView()
            }
            Tab("設定", systemImage: "gearshape.fill", value: TabId.settings) {
                SettingsView()
            }
        }
        #if DEBUG
        .onAppear {
            if let tab = DebugSeed.initialTab { selection = tab }
        }
        #endif
    }
}
