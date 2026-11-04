import SwiftData
import SwiftUI

@main
struct VocabBlossomApp: App {
    @State private var settings = AppSettings()
    @State private var sync: SyncService
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: AppModel.schema)
        } catch {
            fatalError("学習データの保存領域を開けませんでした: \(error)")
        }
        self.container = container
        _sync = State(
            initialValue: SyncService(config: SyncService.appConfig(), context: container.mainContext)
        )
    }

    var body: some Scene {
        WindowGroup {
            WordStoreProvider {
                RootView()
            }
                .environment(settings)
                .environment(sync)
                .environment(\.wordAssist, sync.config.map { WordAssistClient(config: $0) })
                .environment(\.passageFetcher, sync.config.map { PassageClient(config: $0) })
                .tint(Theme.accent)
                .task {
                    #if DEBUG
                    if DebugSeed.isEnabled {
                        DebugSeed.apply(context: container.mainContext, settings: settings)
                    }
                    #endif
                    sync.startObservingChanges()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 起動時とアプリに戻ったときにサーバーの変更を取り込む
            if phase == .active {
                Task { await sync.syncNow() }
            }
        }
    }
}

/// SwiftData に保存するモデルの一覧。アプリとテストで同じものを使う
enum AppModel {
    static var schema: Schema {
        Schema([
            WordProgress.self, AnswerLog.self, WordGroup.self, CustomWord.self, SyncDeletion.self,
        ])
    }
}
