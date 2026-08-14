import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

@Suite("学習進捗の記録")
struct LearningEngineTests {
    let now = TestDate.at(2026, 8, 14)
    let context: ModelContext
    let engine: LearningEngine

    init() throws {
        let container = try ModelContainer(
            for: WordProgress.self, AnswerLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        engine = LearningEngine(context: context)
    }

    private func logs() throws -> [AnswerLog] {
        try context.fetch(
            FetchDescriptor<AnswerLog>(sortBy: [SortDescriptor(\.answeredAt)])
        )
    }

    @Test("初めての正解で進捗レコードが作られ、芽になる")
    func firstCorrectCreatesProgress() throws {
        engine.record(wordId: "a1-0001", correct: true, quizType: .enToJa, kind: .new, now: now)

        let progress = try #require(engine.progress(for: "a1-0001"))
        #expect(progress.stage == 1)
        #expect(DateUtil.daysBetween(now, progress.dueAt) == 1)
        #expect(progress.learnedAt == now)
        #expect(progress.known == false)

        let logs = try logs()
        #expect(logs.count == 1)
        #expect(logs[0].dateKey == "2026-08-14")
        #expect(logs[0].kind == .new)
        #expect(logs[0].stageAfter == 1)
    }

    @Test("未学習の語を間違えても芽にして翌日に乗せる")
    func firstIncorrectStillBecomesSprout() throws {
        engine.record(wordId: "a1-0002", correct: false, quizType: .enToJa, kind: .new, now: now)
        let progress = try #require(engine.progress(for: "a1-0002"))
        #expect(progress.stage == SRS.minLearnedStage)
        #expect(DateUtil.daysBetween(now, progress.dueAt) == 1)
    }

    @Test("復習の正解でステージが上がり、次回が伸びる")
    func reviewAdvancesStage() throws {
        engine.record(wordId: "a1-0003", correct: true, quizType: .enToJa, kind: .new, now: now)
        let later = DateUtil.addDays(now, 1)
        engine.record(
            wordId: "a1-0003", correct: true, quizType: .enToJa, kind: .review, now: later
        )

        let progress = try #require(engine.progress(for: "a1-0003"))
        #expect(progress.stage == 2)
        #expect(DateUtil.daysBetween(later, progress.dueAt) == 3)
        #expect(progress.learnedAt == now)
        #expect(progress.updatedAt == later)
    }

    @Test("再出題はステージも次回復習日も動かさない")
    func requeueDoesNotChangeSchedule() throws {
        engine.record(wordId: "a1-0004", correct: true, quizType: .enToJa, kind: .new, now: now)
        let before = try #require(engine.progress(for: "a1-0004"))
        let stage = before.stage
        let dueAt = before.dueAt

        engine.record(
            wordId: "a1-0004", correct: false, quizType: .enToJa, kind: .requeue, now: now
        )
        let after = try #require(engine.progress(for: "a1-0004"))
        #expect(after.stage == stage)
        #expect(after.dueAt == dueAt)
        #expect(try logs().last?.kind == .requeue)
        #expect(try logs().last?.stageAfter == stage)
    }

    @Test("未学習の語の再出題ではレコードを作らない")
    func requeueOnUnknownWordDoesNotCreateProgress() throws {
        engine.record(
            wordId: "a1-0005", correct: false, quizType: .enToJa, kind: .requeue, now: now
        )
        #expect(engine.progress(for: "a1-0005") == nil)
        #expect(try logs().count == 1)
    }

    @Test("「もう知ってる」は開花（5）扱いで、ログは残さない")
    func markKnownSkipsAhead() throws {
        engine.markKnown(wordId: "a1-0006", now: now)
        let progress = try #require(engine.progress(for: "a1-0006"))
        #expect(progress.stage == SRS.maxStage)
        #expect(progress.known)
        #expect(DateUtil.daysBetween(now, progress.dueAt) == 90)
        #expect(try logs().isEmpty)
    }

    @Test("既知語をまとめて登録できる（保存は 1 回、ログは残さない）")
    func markKnownInBulk() throws {
        let wordIds = (1...5).map { String(format: "a1-%04d", $0 + 100) }
        engine.markKnown(wordIds: wordIds, now: now)

        for wordId in wordIds {
            let progress = try #require(engine.progress(for: wordId))
            #expect(progress.stage == SRS.maxStage)
            #expect(progress.known)
            #expect(DateUtil.daysBetween(now, progress.dueAt) == 90)
        }
        #expect(try context.fetch(FetchDescriptor<WordProgress>()).count == wordIds.count)
        #expect(try logs().isEmpty)
    }

    @Test("すでに学習済みの語を既知登録しても重複しない")
    func markKnownOnLearnedWord() throws {
        engine.record(wordId: "a1-0200", correct: true, quizType: .enToJa, kind: .new, now: now)
        engine.markKnown(wordIds: ["a1-0200"], now: now)

        let all = try context.fetch(FetchDescriptor<WordProgress>())
        #expect(all.count == 1)
        #expect(all[0].stage == SRS.maxStage)
        #expect(all[0].known)
    }

    @Test("同じ単語の進捗は 1 レコードだけ")
    func progressIsUniquePerWord() throws {
        for _ in 0..<3 {
            engine.record(
                wordId: "a1-0007", correct: true, quizType: .enToJa, kind: .review, now: now
            )
        }
        let all = try context.fetch(FetchDescriptor<WordProgress>())
        #expect(all.filter { $0.wordId == "a1-0007" }.count == 1)
        #expect(try logs().count == 3)
    }
}
