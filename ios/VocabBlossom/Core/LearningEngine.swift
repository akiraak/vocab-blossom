import Foundation
import SwiftData

/// 学習進捗の読み書き。SwiftData に触るのはこの層だけにする。
struct LearningEngine {
    let context: ModelContext

    func progress(for wordId: String) -> WordProgress? {
        var descriptor = FetchDescriptor<WordProgress>(
            predicate: #Predicate { $0.wordId == wordId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 1 回答を記録する。
    ///
    /// - 再出題（`.requeue`）はステージ・次回復習日を動かさず、ログだけ残す
    /// - それ以外は SRS の遷移を適用し、未学習の語なら進捗レコードを作る
    @discardableResult
    func record(
        wordId: String,
        correct: Bool,
        quizType: QuizType,
        kind: AnswerKind,
        now: Date = .now
    ) -> Int {
        let existing = progress(for: wordId)
        let stageAfter: Int

        if kind == .requeue {
            stageAfter = existing?.stage ?? SRS.minLearnedStage
        } else {
            let result = SRS.applyAnswer(
                prevStage: existing?.stage ?? 0, correct: correct, now: now
            )
            stageAfter = result.stage
            apply(result, to: existing, wordId: wordId, now: now)
        }

        context.insert(
            AnswerLog(
                wordId: wordId,
                answeredAt: now,
                dateKey: DateUtil.dateKey(now),
                correct: correct,
                quizType: quizType,
                kind: kind,
                stageAfter: stageAfter
            )
        )
        save()
        return stageAfter
    }

    /// 「もう知ってる」。既知語を早く畑から片付ける
    func markKnown(wordId: String, now: Date = .now) {
        markKnown(wordIds: [wordId], now: now)
    }

    /// 既知語をまとめて登録する。
    ///
    /// 数百語を一度に入れるので、既存レコードは 1 回のフェッチでまとめて引き、保存も最後の 1 回だけ行う。
    func markKnown(wordIds: [String], now: Date = .now) {
        let targets = Set(wordIds)
        guard !targets.isEmpty else { return }

        let existing = (try? context.fetch(
            FetchDescriptor<WordProgress>(predicate: #Predicate { targets.contains($0.wordId) })
        )) ?? []
        let existingByWordId = Dictionary(
            existing.map { ($0.wordId, $0) }, uniquingKeysWith: { first, _ in first }
        )

        let result = SRS.applyKnown(now: now)
        for wordId in targets {
            apply(result, to: existingByWordId[wordId], wordId: wordId, now: now, known: true)
        }
        save()
    }

    private func apply(
        _ result: SRS.Result,
        to existing: WordProgress?,
        wordId: String,
        now: Date,
        known: Bool = false
    ) {
        if let existing {
            existing.stage = result.stage
            existing.dueAt = result.dueAt
            existing.updatedAt = now
            if known { existing.known = true }
        } else {
            context.insert(
                WordProgress(
                    wordId: wordId,
                    stage: result.stage,
                    dueAt: result.dueAt,
                    learnedAt: now,
                    updatedAt: now,
                    known: known
                )
            )
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // 保存に失敗しても学習は続けられるようにする（次の回答で再度保存される）
            assertionFailure("学習データの保存に失敗しました: \(error)")
        }
    }
}

extension WordProgress {
    var snapshot: ProgressSnapshot {
        ProgressSnapshot(wordId: wordId, stage: stage, dueAt: dueAt)
    }
}

extension AnswerLog {
    var snapshot: Dashboard.LogSnapshot {
        Dashboard.LogSnapshot(wordId: wordId, dateKey: dateKey, correct: correct, kind: kind)
    }
}
