#if DEBUG
import Foundation
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

    /// 既知語の一括登録画面を最初から出す
    static var showsKnownWordsPicker: Bool { variant == .knownWords }

    /// 起動直後に開くタブ
    static var initialTab: MainTabView.TabId? {
        switch variant {
        case .words: .words
        case .stats: .stats
        case .settings: .settings
        default: nil
        }
    }

    /// 学習途中の状態（庭に花が咲き、復習も溜まっている）を作る。
    static func apply(context: ModelContext, settings: AppSettings, now: Date = .now) {
        let variant = variant
        settings.hasOnboarded = true

        try? context.delete(model: WordProgress.self)
        try? context.delete(model: AnswerLog.self)

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
}
#endif
