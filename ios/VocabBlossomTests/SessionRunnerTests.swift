import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

@Suite("セッション進行")
struct SessionRunnerTests {
    let now = TestDate.at(2026, 8, 14)
    let store = WordStore.shared
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

    private func runner(_ plan: SessionPlan) -> SessionRunner {
        SessionRunner(
            plan: plan,
            engine: engine,
            store: store,
            rng: SeededRNG(seed: 42),
            clock: { now }
        )
    }

    private func currentQuiz(_ runner: SessionRunner) throws -> (Quiz, AnswerKind) {
        guard case .quiz(let quiz, let kind) = runner.step else {
            Issue.record("クイズではなく \(runner.step) が表示されている")
            throw CancellationError()
        }
        return (quiz, kind)
    }

    private func answerCorrectly(_ runner: SessionRunner) throws {
        let (quiz, _) = try currentQuiz(runner)
        runner.answer(choiceIndex: quiz.answerIndex)
        runner.next()
    }

    private func answerIncorrectly(_ runner: SessionRunner) throws {
        let (quiz, _) = try currentQuiz(runner)
        runner.answer(choiceIndex: (quiz.answerIndex + 1) % quiz.choices.count)
        runner.next()
    }

    @Test("復習 → 新規学習（提示 → 直後クイズ）の順に進む")
    func orderIsReviewThenNewWords() throws {
        let plan = SessionPlan(
            reviewWordIds: ["a1-0001"],
            newWordIds: ["a1-0010", "a1-0011"]
        )
        let runner = runner(plan)

        let (review, reviewKind) = try currentQuiz(runner)
        #expect(review.word.id == "a1-0001")
        #expect(reviewKind == .review)
        try answerCorrectly(runner)

        // 5 語ミニバッチなので、この 2 語はまとめて提示されてからクイズになる
        guard case .present(let first) = runner.step else {
            Issue.record("提示カードが出ていない")
            return
        }
        #expect(first.id == "a1-0010")
        runner.next()

        guard case .present(let second) = runner.step else {
            Issue.record("2 語目の提示カードが出ていない")
            return
        }
        #expect(second.id == "a1-0011")
        runner.next()

        let (firstQuiz, kind) = try currentQuiz(runner)
        #expect(firstQuiz.word.id == "a1-0010")
        #expect(kind == .new)
        #expect(firstQuiz.type == .enToJa, "新規の直後クイズは英→日")
    }

    @Test("復習の出題形式はステージに連動する")
    func reviewQuizTypeFollowsStage() throws {
        context.insert(
            WordProgress(
                wordId: "a1-0004", stage: 4, dueAt: now, learnedAt: now, updatedAt: now
            )
        )
        try context.save()

        let runner = runner(SessionPlan(reviewWordIds: ["a1-0004"]))
        let (quiz, _) = try currentQuiz(runner)
        #expect(quiz.type == .jaToEn)
    }

    @Test("全問正解すると再出題なしで締めに進む")
    func allCorrectFinishes() throws {
        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001", "a1-0002"]))
        try answerCorrectly(runner)
        try answerCorrectly(runner)
        #expect(runner.isFinished)
        #expect(runner.stats.answered == 2)
        #expect(runner.stats.correct == 2)
        #expect(runner.stats.accuracy == 1.0)
    }

    @Test("間違えたカードはセッション末尾で再出題される")
    func incorrectCardIsRequeued() throws {
        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001", "a1-0002"]))
        try answerIncorrectly(runner)
        try answerCorrectly(runner)

        let (requeued, kind) = try currentQuiz(runner)
        #expect(requeued.word.id == "a1-0001")
        #expect(kind == .requeue)
        try answerCorrectly(runner)
        #expect(runner.isFinished)
    }

    @Test("再出題は同一カード 2 回まで")
    func requeueIsCappedAtTwo() throws {
        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001"]))
        try answerIncorrectly(runner)  // 1 回目の再出題を積む
        try answerIncorrectly(runner)  // 2 回目の再出題を積む
        try answerIncorrectly(runner)  // ここで打ち切り
        #expect(runner.isFinished)
        #expect(runner.stats.answered == 3)
    }

    @Test("再出題の正誤はステージ・次回復習日を動かさない")
    func requeueDoesNotAffectSchedule() throws {
        context.insert(
            WordProgress(
                wordId: "a1-0001", stage: 3,
                dueAt: DateUtil.startOfDay(now), learnedAt: now, updatedAt: now
            )
        )
        try context.save()

        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001"]))
        try answerIncorrectly(runner)
        let afterReview = try #require(engine.progress(for: "a1-0001"))
        #expect(afterReview.stage == 2)
        let dueAfterReview = afterReview.dueAt

        try answerCorrectly(runner)  // 再出題で正解
        let afterRequeue = try #require(engine.progress(for: "a1-0001"))
        #expect(afterRequeue.stage == 2)
        #expect(afterRequeue.dueAt == dueAfterReview)
    }

    @Test("「もう知ってる」は直後クイズを飛ばし、つぼみ（4）にする")
    func markKnownSkipsTheFollowUpQuiz() throws {
        let runner = runner(SessionPlan(newWordIds: ["a1-0010", "a1-0011"]))
        guard case .present = runner.step else {
            Issue.record("提示カードが出ていない")
            return
        }
        runner.markKnown()

        guard case .present(let second) = runner.step else {
            Issue.record("2 語目の提示カードが出ていない")
            return
        }
        #expect(second.id == "a1-0011")
        runner.next()

        // 残るクイズは 2 語目だけ
        let (quiz, _) = try currentQuiz(runner)
        #expect(quiz.word.id == "a1-0011")
        try answerCorrectly(runner)
        #expect(runner.isFinished)

        let known = try #require(engine.progress(for: "a1-0010"))
        #expect(known.stage == SRS.knownStage)
        #expect(known.known)
        #expect(runner.stats.knownWordIds == ["a1-0010"])
    }

    @Test("開花に到達した語を締めに記録する")
    func blossomedWordsAreCollected() throws {
        context.insert(
            WordProgress(
                wordId: "a1-0001", stage: 4, dueAt: now, learnedAt: now, updatedAt: now
            )
        )
        try context.save()

        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001"]))
        try answerCorrectly(runner)
        #expect(runner.stats.blossomedWordIds == ["a1-0001"])
    }

    @Test("回答は 1 問につき 1 回だけ受け付ける")
    func answeringTwiceIsIgnored() throws {
        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001"]))
        let (quiz, _) = try currentQuiz(runner)
        runner.answer(choiceIndex: quiz.answerIndex)
        runner.answer(choiceIndex: (quiz.answerIndex + 1) % quiz.choices.count)
        #expect(runner.stats.answered == 1)
        #expect(runner.selectedIndex == quiz.answerIndex)
        #expect(runner.lastAnswerWasCorrect == true)
    }

    @Test("進捗は 0 から始まり、終わると 1 になる")
    func progressGoesFromZeroToOne() throws {
        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001", "a1-0002"]))
        #expect(runner.progress == 0)
        #expect(runner.remainingCount == 2)
        try answerCorrectly(runner)
        #expect(runner.progress == 0.5)
        try answerCorrectly(runner)
        #expect(runner.progress == 1)
        #expect(runner.remainingCount == 0)
    }

    @Test("空のプランはすぐ締めになる")
    func emptyPlanFinishesImmediately() {
        let runner = runner(SessionPlan())
        #expect(runner.isFinished)
        #expect(runner.stats.answered == 0)
    }

    @Test("回答するたびに保存され、途中で閉じても記録が残る")
    func answersArePersistedImmediately() throws {
        let runner = runner(SessionPlan(reviewWordIds: ["a1-0001", "a1-0002"]))
        try answerCorrectly(runner)
        let logs = try context.fetch(FetchDescriptor<AnswerLog>())
        #expect(logs.count == 1)
        #expect(logs[0].wordId == "a1-0001")
        #expect(engine.progress(for: "a1-0001") != nil)
    }
}
