import SwiftData
import SwiftUI

@main
struct VocabBlossomApp: App {
    @State private var settings = AppSettings()
    @State private var sync: SyncService
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        Self.preferJapanese()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: AppModel.schema)
        } catch {
            fatalError("学習データの保存領域を開けませんでした: \(error)")
        }
        self.container = container
        let config = SyncService.appConfig()
        _sync = State(initialValue: SyncService(config: config, context: container.mainContext))
        // グループの読み上げ・学習中の読み上げの声（Gemini TTS）。サーバーの設定が無ければ OS 内蔵の声で読む
        GeminiReadAloudSpeaker.shared.fetcher = config.map { SpeechClient(config: $0) }
        GeminiReadAloudSpeaker.quiz.fetcher = config.map { SpeechClient(config: $0) }
        #if DEBUG
        if DebugSeed.variant == .groupReadAloud {
            GeminiReadAloudSpeaker.shared.fetcher = DebugSpeechFetcher()
        }
        if [.groupReadAloud, .groupFillBlank, .groupFillBlankTyping, .session, .groupLearn, .groupDrill]
            .contains(DebugSeed.variant) {
            GeminiReadAloudSpeaker.quiz.fetcher = DebugSpeechFetcher()
        }
        #endif
    }

    /// このアプリの言語の並びの先頭を日本語にする（iPhone の「設定 > アプリ > 言語」で日本語を選んだのと同じ）。
    ///
    /// 漢字は日本語と中国語で同じ文字コードなので、iPhone の言語で日本語が先頭でないと、iOS は中国語のフォントで描く
    /// （「骨」「直」などの字形が変わる）。言語の並びは起動時に読まれるので、書きかえた回は次の起動から効く。
    /// docs/plans/archive/japanese-font-and-voice.md
    static func preferJapanese(defaults: UserDefaults = .standard) {
        let key = "AppleLanguages"
        let current = defaults.stringArray(forKey: key) ?? []
        guard current.first?.hasPrefix("ja") != true else { return }
        defaults.set(["ja-JP"] + current.filter { !$0.hasPrefix("ja") }, forKey: key)
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
                .environment(\.fillBlankChecker, sync.config.map { FillBlankCheckClient(config: $0) })
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
            GroupAnswerLog.self,
        ])
    }
}
