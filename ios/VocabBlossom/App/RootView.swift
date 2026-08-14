import SwiftUI

/// 下部タブ + セッションのフルスクリーンモーダル、という MVP の画面構造。
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
    var body: some View {
        TabView {
            Tab("ホーム", systemImage: "leaf.fill") {
                HomeView()
            }
            Tab("単語帳", systemImage: "book.fill") {
                WordListView()
            }
            Tab("統計", systemImage: "chart.bar.fill") {
                StatsView()
            }
            Tab("設定", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}
