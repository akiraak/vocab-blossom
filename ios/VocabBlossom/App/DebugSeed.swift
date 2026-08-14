#if DEBUG
import Foundation
import SwiftData

/// 開発中に画面を確認するためのダミーデータ投入。
///
/// `SIMCTL_CHILD_VOCAB_SEED_DEMO=1 xcrun simctl launch booted com.akiraak.VocabBlossom`
/// のように環境変数を渡したときだけ動く。Release ビルドには含まれない。
enum DebugSeed {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["VOCAB_SEED_DEMO"] == "1"
    }

    /// 学習途中の状態（庭に花が咲き、復習も溜まっている）を作る。
    static func apply(context: ModelContext, settings: AppSettings, now: Date = .now) {
        settings.hasOnboarded = true

        try? context.delete(model: WordProgress.self)
        try? context.delete(model: AnswerLog.self)

        let pool = WordStore.shared.newWordPool(level: settings.level)
        // ステージがばらけるよう 45 語を 1〜5 に配り、一部は期限切れにする
        for (offset, word) in pool.prefix(45).enumerated() {
            let stage = offset % 5 + 1
            let dueOffset = offset % 4 == 0 ? -(offset % 3 + 1) : offset % 7 + 1
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

        // 直近 2 週間のうち 5 日を除いて学習した記録（ストリークと日別グラフ用）
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
        try? context.save()
    }
}
#endif
