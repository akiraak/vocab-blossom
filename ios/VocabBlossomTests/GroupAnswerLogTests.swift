import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

@Suite("グループの問題に答えた記録")
struct GroupAnswerLogTests {
    let now = TestDate.at(2026, 11, 6)
    let store = WordStore.shared
    let context: ModelContext
    let engine: LearningEngine
    let groupId = UUID()

    init() throws {
        let container = try ModelContainer(
            for: AppModel.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        engine = LearningEngine(context: context)
    }

    private func logs() throws -> [GroupAnswerLog] {
        try context.fetch(FetchDescriptor<GroupAnswerLog>(sortBy: [SortDescriptor(\.answeredAt)]))
    }

    private func answerLogs() throws -> [AnswerLog] {
        try context.fetch(FetchDescriptor<AnswerLog>())
    }

    private func currentQuiz(_ runner: SessionRunner) throws -> Quiz {
        guard case .quiz(let quiz, _) = runner.step else {
            Issue.record("クイズではなく \(runner.step) が表示されている")
            throw CancellationError()
        }
        return quiz
    }

    private func answer(_ runner: SessionRunner, correct: Bool) throws {
        let quiz = try currentQuiz(runner)
        runner.answer(choiceIndex: correct ? quiz.answerIndex : (quiz.answerIndex + 1) % quiz.choices.count)
        runner.next()
    }

    private func context(_ source: GroupAnswerSource) -> GroupAnswerContext {
        GroupAnswerContext(groupId: groupId, source: source)
    }

    // MARK: - SessionRunner

    @Test("グループのドリルは 1 回答 1 行を残し、再出題も数える。SRS の記録は残さない")
    func drillRecordsEachAnswer() throws {
        let runner = SessionRunner(
            drillWordIds: ["a1-0001", "a1-0002"], engine: engine, store: store,
            group: context(.drill), rng: SeededRNG(seed: 1), clock: { now }
        )
        try answer(runner, correct: false)
        try answer(runner, correct: true)
        try answer(runner, correct: true)  // a1-0001 の再出題
        #expect(runner.isFinished)

        let logs = try logs()
        #expect(logs.count == 3)
        #expect(logs.allSatisfy { $0.groupId == groupId && $0.source == .drill })
        #expect(logs.map(\.wordId) == ["a1-0001", "a1-0002", "a1-0001"])
        #expect(logs.map(\.correct) == [false, true, true])
        #expect(logs.map(\.kind) == [.review, .review, .requeue])
        #expect(try answerLogs().isEmpty)
        #expect(engine.progress(for: "a1-0001") == nil)
    }

    @Test("穴埋めモード（組み立て済みの問題）も、形式と入口を残す")
    func preparedDrillRecords() throws {
        let word = try #require(store.word(id: "a1-0001"))
        var builder = QuizBuilder(store: store, rng: SeededRNG(seed: 2))
        let quiz = builder.make(for: word, type: .fillBlank)
        let runner = SessionRunner(
            drillQuizzes: [quiz], engine: engine, store: store,
            group: context(.fillBlank), rng: SeededRNG(seed: 2), clock: { now }
        )
        try answer(runner, correct: true)

        let log = try #require(try logs().first)
        #expect(log.wordId == "a1-0001")
        #expect(log.quizType == quiz.type)
        #expect(log.source == .fillBlank)
        #expect(log.answeredAt == now)
        #expect(try answerLogs().isEmpty)
    }

    @Test("グループの「学習する」は、今までどおり SRS にも残す")
    func learningRecordsBoth() throws {
        let runner = SessionRunner(
            plan: SessionPlan(reviewWordIds: ["a1-0001"], newWordIds: []), engine: engine, store: store,
            group: context(.learning), rng: SeededRNG(seed: 3), clock: { now }
        )
        try answer(runner, correct: true)

        #expect(try logs().map(\.source) == [.learning])
        #expect(try answerLogs().count == 1)
    }

    @Test("グループの指定が無ければ残さない（毎日の学習・ドリル）")
    func noGroupNoRecord() throws {
        let learning = SessionRunner(
            plan: SessionPlan(reviewWordIds: ["a1-0001"], newWordIds: []), engine: engine, store: store,
            rng: SeededRNG(seed: 4), clock: { now }
        )
        try answer(learning, correct: true)
        let drill = SessionRunner(
            drillWordIds: ["a1-0002"], engine: engine, store: store, rng: SeededRNG(seed: 4), clock: { now }
        )
        try answer(drill, correct: true)

        #expect(try logs().isEmpty)
        #expect(try answerLogs().count == 1)
    }

    // MARK: - 集計

    private func answer(_ wordId: String, _ correct: Bool, day: Int) -> GroupStudy.Answer {
        GroupStudy.Answer(wordId: wordId, answeredAt: TestDate.at(2026, 11, day), correct: correct)
    }

    @Test("達成度は、最後に答えたときに正解だった語の割合。答えていない語は未達成")
    func activityUsesLatestAnswer() {
        let activity = GroupStudy.activity(
            wordIds: ["w1", "w2", "w3", "w4"],
            answers: [
                // 並びは時刻順でなくてもよい
                answer("w1", true, day: 3),
                answer("w1", false, day: 2),
                answer("w2", true, day: 2),
                answer("w2", false, day: 3),
                answer("w3", true, day: 1),
            ]
        )
        #expect(activity.answerCount == 5)
        #expect(activity.achieved == 2)  // w1・w3
        #expect(activity.total == 4)
        #expect(activity.achievement == 0.5)
        #expect(GroupActivityText.line(activity) == "回答 5 回・達成 50%")
    }

    @Test("グループから外した語は達成度に数えない（回答数には残る）")
    func activityIgnoresRemovedWords() {
        let activity = GroupStudy.activity(
            wordIds: ["w1"],
            answers: [answer("w1", true, day: 1), answer("gone", true, day: 1)]
        )
        #expect(activity.answerCount == 2)
        #expect(activity.achieved == 1)
        #expect(activity.achievement == 1)
    }

    @Test("空のグループは達成度なし。1 語でも残っていれば 100% にしない")
    func activityEdgeCases() {
        let empty = GroupStudy.activity(wordIds: [], answers: [])
        #expect(empty == GroupStudy.Activity())
        #expect(empty.achievement == nil)
        #expect(GroupActivityText.line(empty) == "回答 0 回")

        let ids = (1...200).map { "w\($0)" }
        let almost = GroupStudy.activity(
            wordIds: ids, answers: ids.dropLast().map { answer($0, true, day: 1) }
        )
        #expect(GroupActivityText.percent(almost) == 99)
    }

    // MARK: - 消すとき

    @Test("グループを消すと、そのグループの記録も消える（ほかのグループの記録は残る）")
    func deletingGroupPurgesLogs() throws {
        let editor = GroupEditor(context: context)
        let group = editor.createGroup(name: "A", now: now)
        let other = editor.createGroup(name: "B", now: now)
        for target in [group, other] {
            engine.recordGroupAnswer(
                GroupAnswerContext(groupId: target.id, source: .drill),
                wordId: "a1-0001", correct: true, quizType: .enToJa, kind: .review, now: now
            )
        }
        editor.delete(group, now: now)

        #expect(try logs().map(\.groupId) == [other.id])
    }

    @Test("マイ単語を消すと、その語の記録も消える")
    func deletingCustomWordPurgesLogs() throws {
        let editor = GroupEditor(context: context)
        let group = editor.createGroup(name: "A", now: now)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム", pos: .noun),
            addingTo: group,
            now: now
        )
        for wordId in [custom.wordId, "a1-0001"] {
            engine.recordGroupAnswer(
                GroupAnswerContext(groupId: group.id, source: .drill),
                wordId: wordId, correct: true, quizType: .enToJa, kind: .review, now: now
            )
        }
        editor.deleteCustomWord(id: custom.wordId, now: now)

        #expect(try logs().map(\.wordId) == ["a1-0001"])
    }

    // MARK: - バックアップ

    @Test("バックアップに入り、読み込むと戻る")
    func backupRoundTrip() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "group-answer-\(UUID().uuidString)")!)
        engine.recordGroupAnswer(
            GroupAnswerContext(groupId: groupId, source: .fillBlank),
            wordId: "a1-0001", correct: false, quizType: .fillBlank, kind: .requeue, now: now
        )
        let data = try BackupService.export(context: context, settings: settings, now: now)

        let other = ModelContext(
            try ModelContainer(
                for: AppModel.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
        other.insert(
            GroupAnswerLog(
                groupId: UUID(), wordId: "zzz", answeredAt: now, correct: true, quizType: .enToJa,
                source: .drill, kind: .review
            )
        )
        try other.save()
        let archive = try BackupService.restore(from: data, context: other, settings: settings)

        #expect(archive.version == 4)
        let restored = try other.fetch(FetchDescriptor<GroupAnswerLog>())
        #expect(restored.count == 1)
        let log = try #require(restored.first)
        #expect(log.groupId == groupId)
        #expect(log.wordId == "a1-0001")
        #expect(log.correct == false)
        #expect(log.quizType == .fillBlank)
        #expect(log.source == .fillBlank)
        #expect(log.kind == .requeue)
        #expect(log.answeredAt == now)
    }

    @Test("記録の無い古い形式（v3）のファイルも読める")
    func backupReadsVersion3() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "group-answer-\(UUID().uuidString)")!)
        engine.recordGroupAnswer(
            GroupAnswerContext(groupId: groupId, source: .drill),
            wordId: "a1-0001", correct: true, quizType: .enToJa, kind: .review, now: now
        )
        var archive = BackupArchive(
            exportedAt: now,
            settings: BackupArchive.Settings(
                level: .a1, newWordsPerDay: 10, reviewLimitPerDay: 60, soundEnabled: true
            ),
            progress: [],
            logs: [],
            groups: [],
            customWords: []
        )
        archive.version = 3
        let data = try BackupService.encoder.encode(archive)
        #expect(!String(decoding: data, as: UTF8.self).contains("groupAnswers"))

        try BackupService.restore(from: data, context: context, settings: settings)
        // 置き換え方式なので、今の記録は消えて空になる
        #expect(try logs().isEmpty)
    }
}
