#if DEBUG
import Foundation
import SwiftUI
import SwiftData

/// 開発中に画面を確認するためのダミーデータ投入。
///
/// `SIMCTL_CHILD_VOCAB_SEED_DEMO=1 xcrun simctl launch booted com.akiraak.VocabBlossom`
/// のように環境変数を渡したときだけ動く。Release ビルドには含まれない。
///
/// - `VOCAB_SEED_DEMO=1`: 学習途中の状態を作る
/// - `VOCAB_DEMO_SCREEN=session`: 起動直後にセッションを開く（復習から始まる）
/// - `VOCAB_DEMO_SCREEN=session-new`: 復習は無く、新規学習の提示カードから始まる
/// - `VOCAB_DEMO_SCREEN=session-summary`: 出題が無い状態（締め画面）
/// - `VOCAB_DEMO_SCREEN=words|stats|settings`: そのタブを開いた状態で起動する
/// - `VOCAB_DEMO_SCREEN=fresh`: オンボーディング済み・学習記録なしの状態
/// - `VOCAB_DEMO_SCREEN=known-words`: 既知語の一括登録画面
/// - `VOCAB_DEMO_SCREEN=groups`: グループタブ（同梱語 + 自作語のグループ入り）を開く
/// - `VOCAB_DEMO_SCREEN=group-detail`: 上のグループの詳細を開く
/// - `VOCAB_DEMO_SCREEN=group-learn` / `group-drill` / `group-fill-blank`: グループの学習 / ドリル / 穴埋めを起動直後に開く
/// - `VOCAB_DEMO_SCREEN=group-read-aloud`: グループの読み上げを起動直後に開く（開くと読み始める）
/// - `VOCAB_DEMO_SCREEN=fill-blank-preparing`: 穴埋めの文章を作る画面（空のキャッシュ・偽のサーバーでゆっくり作る）
/// - `VOCAB_DEMO_SCREEN=word-picker`: グループの「単語を追加」を、単語帳に無い語で検索した状態で開く
///   （`VOCAB_DEMO_QUERY=proper` を足すと、その語で検索欄に入力中の状態で開く）
/// - `VOCAB_DEMO_SCREEN=word-editor`: グループの「単語を追加」から、例文に単語が無い下書きで自作語のエディタを開く
/// - `VOCAB_DEMO_SCREEN=word-editor-loading`: 上のエディタを、AI で調べている途中の表示のまま開く
enum DebugSeed {
    enum Variant: String {
        case none
        case session
        case sessionNew = "session-new"
        case sessionSummary = "session-summary"
        case words
        case stats
        case settings
        /// オンボーディング済み・学習記録なし（空の庭）
        case fresh
        /// 既知語の一括登録画面
        case knownWords = "known-words"
        /// グループタブ
        case groups
        case groupDetail = "group-detail"
        case groupLearn = "group-learn"
        case groupDrill = "group-drill"
        case groupFillBlank = "group-fill-blank"
        case groupReadAloud = "group-read-aloud"
        case fillBlankPreparing = "fill-blank-preparing"
        case groupSelect = "group-select"
        case wordPicker = "word-picker"
        case wordEditor = "word-editor"
        case wordEditorLoading = "word-editor-loading"
        case wordAssistResult = "word-assist-result"
        /// 意味が 2 つある下書きのエディタ
        case wordEditorSenses = "word-editor-senses"
        /// 意味が 2 つある自作語（cram）の単語詳細
        case wordDetailSenses = "word-detail-senses"
        /// 意味が 2 つある自作語（cram）だけのドリル
        case drillSenses = "drill-senses"

        var seedsGroups: Bool {
            switch self {
            case .groups, .groupDetail, .groupLearn, .groupDrill, .groupFillBlank, .groupReadAloud,
                 .fillBlankPreparing, .groupSelect,
                 .wordPicker, .wordEditor, .wordEditorLoading, .wordAssistResult,
                 .wordEditorSenses, .wordDetailSenses, .drillSenses:
                true
            default: false
            }
        }

        /// 学習済みの単語を作るか
        var hasProgress: Bool { self != .fresh && self != .knownWords }
        /// 期限切れの復習を作るか
        var hasDueReviews: Bool { self == .none || self == .session }
        /// 今日の新規語をすでに消化済みにするか
        var newWordsExhausted: Bool { self == .sessionSummary }
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["VOCAB_SEED_DEMO"] == "1"
    }

    static var variant: Variant {
        Variant(rawValue: ProcessInfo.processInfo.environment["VOCAB_DEMO_SCREEN"] ?? "") ?? .none
    }

    /// 起動直後にセッションを開く
    static var autoStartSession: Bool {
        switch variant {
        case .session, .sessionNew, .sessionSummary: true
        default: false
        }
    }

    /// グループ詳細を最初から開く
    static var opensFirstGroup: Bool {
        [.groupDetail, .groupLearn, .groupDrill, .groupFillBlank, .groupReadAloud, .fillBlankPreparing,
                 .groupSelect,
         .wordPicker, .wordEditor, .wordEditorLoading, .wordAssistResult,
         .wordEditorSenses, .wordDetailSenses, .drillSenses]
            .contains(variant)
    }

    /// 既知語の一括登録画面を最初から出す
    static var showsKnownWordsPicker: Bool { variant == .knownWords }

    /// 起動直後に開くタブ
    static var initialTab: MainTabView.TabId? {
        switch variant {
        case .words: .words
        case .stats: .stats
        case .settings: .settings
        case .groups, .groupDetail, .groupLearn, .groupDrill, .groupFillBlank, .groupReadAloud,
             .fillBlankPreparing, .groupSelect,
             .wordPicker, .wordEditor, .wordEditorLoading, .wordAssistResult,
             .wordEditorSenses, .wordDetailSenses, .drillSenses:
            .groups
        default: nil
        }
    }

    /// `word-picker` で検索しておく語（単語帳に無い）
    static let demoMissingQuery = "commute"
    /// `VOCAB_DEMO_QUERY=proper` のように渡すと、その語で検索し、検索欄に入力中の状態で開く
    static var demoSearchQuery: String? {
        ProcessInfo.processInfo.environment["VOCAB_DEMO_QUERY"]
    }

    /// `word-assist-result` で出す AI の結果（サーバーに聞かずに、調べ終わった状態を見る）
    static let demoCandidates: [WordAssistAPI.Candidate] = [
        WordAssistAPI.Candidate(
            word: "commute", pos: .verb, meaning: "通勤する、通学する",
            example: "I commute to school by bus.", exampleJa: "私はバスで通学します。",
            reason: .exact, bundled: nil
        ),
        WordAssistAPI.Candidate(
            word: "commute", pos: .noun, meaning: "通勤、通学",
            example: "My commute takes an hour.", exampleJa: "私の通勤には 1 時間かかります。",
            reason: .exact, bundled: nil
        ),
    ]

    /// `word-editor` で入れておく下書き（例文に単語が無く、品詞は自動推測のまま）
    static let demoDraft = GroupEditor.WordDraft(
        word: "commute", meaning: "通学する", pos: .noun,
        example: "I go to school by bus.", exampleJa: "私はバスで通学します。"
    )

    /// 学習途中の状態（庭に花が咲き、復習も溜まっている）を作る。
    static func apply(context: ModelContext, settings: AppSettings, now: Date = .now) {
        let variant = variant
        settings.hasOnboarded = true
        // ダミーデータを入れた端末は、この後ふつうに起動してもサーバーと同期しない（本番にダミーを送らない）
        UserDefaults.standard.set(true, forKey: SyncService.Key.disabledByDebugSeed)

        try? context.delete(model: WordProgress.self)
        try? context.delete(model: AnswerLog.self)
        try? context.delete(model: WordGroup.self)
        try? context.delete(model: CustomWord.self)

        guard variant.hasProgress else {
            try? context.save()
            return
        }

        let pool = WordStore.shared.newWordPool(level: settings.level)
        // ステージがばらけるよう 45 語を 1〜5 に配り、一部は期限切れにする
        for (offset, word) in pool.prefix(45).enumerated() {
            let stage = offset % 5 + 1
            let isDue = variant.hasDueReviews && offset % 4 == 0
            let dueOffset = isDue ? -(offset % 3 + 1) : offset % 7 + 1
            context.insert(
                WordProgress(
                    wordId: word.id,
                    stage: stage,
                    dueAt: DateUtil.startOfDay(DateUtil.addDays(now, dueOffset)),
                    learnedAt: DateUtil.addDays(now, -(offset % 20) - 1),
                    updatedAt: now
                )
            )
        }

        // 直近 2 週間のうち数日を除いて学習した記録（ストリークと日別グラフ用）
        for dayOffset in 0..<14 where dayOffset != 3 && dayOffset % 5 != 4 {
            let date = DateUtil.addDays(now, -dayOffset)
            for index in 0..<(6 + dayOffset % 5) {
                context.insert(
                    AnswerLog(
                        wordId: pool[(dayOffset * 7 + index) % 45].id,
                        answeredAt: date,
                        dateKey: DateUtil.dateKey(date),
                        correct: index % 6 != 0,
                        quizType: QuizType.allCases[index % QuizType.allCases.count],
                        kind: index % 3 == 0 ? .new : .review,
                        stageAfter: index % 5 + 1
                    )
                )
            }
        }

        if variant.seedsGroups {
            seedGroups(context: context, pool: pool, now: now)
        }

        if variant.newWordsExhausted {
            // 今日の新規語の枠を使い切った状態にする
            for word in pool.dropFirst(45).prefix(settings.newWordsPerDay) {
                context.insert(
                    AnswerLog(
                        wordId: word.id,
                        answeredAt: now,
                        dateKey: DateUtil.dateKey(now),
                        correct: true,
                        quizType: .enToJa,
                        kind: .new,
                        stageAfter: 1
                    )
                )
                context.insert(
                    WordProgress(
                        wordId: word.id,
                        stage: 1,
                        dueAt: DateUtil.startOfDay(DateUtil.addDays(now, 1)),
                        learnedAt: now,
                        updatedAt: now
                    )
                )
            }
        }
        try? context.save()
    }

    /// 学習済みの語・未学習の語・自作語が混ざったグループを作る
    private static func seedGroups(context: ModelContext, pool: [WordEntry], now: Date) {
        let editor = GroupEditor(context: context)
        let unit = editor.createGroup(name: "小テスト Unit 3", now: now)
        editor.add(wordIds: pool.prefix(4).map(\.id) + pool.dropFirst(60).prefix(6).map(\.id), to: unit)
        editor.createCustomWord(
            GroupEditor.WordDraft(
                word: "take care of", meaning: "〜の世話をする", pos: .phrase,
                example: "I take care of my little sister.", exampleJa: "私は妹の世話をします。"
            ),
            addingTo: unit,
            now: now
        )
        editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム", pos: .noun),
            addingTo: unit,
            now: now
        )
        // 意味が 2 つ（動詞・名詞）ある自作語
        editor.createCustomWord(
            GroupEditor.WordDraft(
                word: "cram", meaning: "詰め込み勉強をする", pos: .verb,
                example: "I crammed for the test last night.", exampleJa: "昨夜はテストのために詰め込み勉強をした。",
                extraSenses: [
                    WordSense(
                        pos: .noun, meaning: "詰め込み勉強",
                        example: "A cram before the test doesn't help much.",
                        exampleJa: "テスト前の詰め込み勉強はあまり役に立たない。"
                    ),
                ]
            ),
            addingTo: unit,
            now: now
        )
        editor.createGroup(name: "教科書の熟語", now: DateUtil.addDays(now, -3))
    }
}

// MARK: - 穴埋めの文章を作る画面の確認用

/// 1 回 1.5 秒かけて、決まった形の文章を返す偽のサーバー。dream だけは作れなかったことにする
nonisolated struct DebugPassageFetcher: PassageFetching {
    /// 画面を描き直しても同じものを使う（作った文章が消えないように）
    static let cache = PassageCache(fileURL: nil)

    func fetch(_ words: [PassageAPI.Word]) async throws -> [PassageAPI.Result] {
        try await Task.sleep(for: .milliseconds(1500))
        return words.map { word in
            let passages = (1...3).map { number in
                Passage(
                    text: "This is passage \(number). It has the word \(word.word) in it for the quiz.",
                    ja: "これは文章 \(number) です。"
                )
            }
            return PassageAPI.Result(id: word.id, passages: word.word == "dream" ? [] : passages)
        }
    }
}

extension View {
    /// `fill-blank-preparing` のときだけ、空のキャッシュと偽のサーバーに差し替える
    @ViewBuilder
    func debugPassagePreparation() -> some View {
        if DebugSeed.variant == .fillBlankPreparing {
            environment(\.passageCache, DebugPassageFetcher.cache)
                .environment(\.passageFetcher, DebugPassageFetcher())
        } else {
            self
        }
    }
}
#endif
