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

    /// グループの問題への 1 回答を記録する（グループ一覧の回答数・達成度に使う）。SRS は動かさない
    func recordGroupAnswer(
        _ group: GroupAnswerContext,
        wordId: String,
        correct: Bool,
        quizType: QuizType,
        kind: AnswerKind,
        now: Date = .now
    ) {
        context.insert(
            GroupAnswerLog(
                groupId: group.groupId,
                wordId: wordId,
                answeredAt: now,
                correct: correct,
                quizType: quizType,
                source: group.source,
                kind: kind
            )
        )
        save()
    }

    /// 進捗を消して未学習（種）に戻す。「もう知ってる」の取り消しに使う
    func forget(wordId: String) {
        guard let existing = progress(for: wordId) else { return }
        context.delete(existing)
        save()
    }

    /// どのグループにも入っていない語のうち、進捗（学習記録）がある語。
    /// 設定の「グループに無い単語の学習記録を消す」の対象（前の版のおまかせ学習・既知語の一括登録・外した語など）
    static func wordIdsOutsideGroups(progressWordIds: [String], groupWordIds: Set<String>) -> Set<String> {
        Set(progressWordIds).subtracting(groupWordIds)
    }

    /// 指定した語の進捗（学習記録）を消して未学習（種）に戻す。消した数を返す。
    ///
    /// 回答の記録（`AnswerLog`）は消さない（連続日数・統計のグラフを残すため）。保存は最後の 1 回だけ
    @discardableResult
    func deleteProgress(wordIds: Set<String>) -> Int {
        guard !wordIds.isEmpty else { return 0 }
        let targets = (try? context.fetch(
            FetchDescriptor<WordProgress>(predicate: #Predicate { wordIds.contains($0.wordId) })
        )) ?? []
        for progress in targets { context.delete(progress) }
        save()
        return targets.count
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
