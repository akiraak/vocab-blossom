import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

/// 決めた綴りを「ほかの正解」として返す偽物。送られた問題を記録する
private final class FakeChecker: FillBlankChecking, @unchecked Sendable {
    let alsoCorrect: [String]
    let error: (any Error)?
    private let lock = NSLock()
    private var sent: [[FillBlankCheckAPI.Item]] = []

    init(alsoCorrect: [String] = [], error: (any Error)? = nil) {
        self.alsoCorrect = alsoCorrect
        self.error = error
    }

    var calls: [[FillBlankCheckAPI.Item]] { lock.withLock { sent } }

    func check(_ items: [FillBlankCheckAPI.Item]) async throws -> [FillBlankCheckAPI.Result] {
        lock.withLock { sent.append(items) }
        if let error { throw error }
        return items.map { item in
            FillBlankCheckAPI.Result(id: item.id, alsoCorrect: item.choices.filter(alsoCorrect.contains))
        }
    }
}

@Suite("穴埋めの選択肢の判定")
struct FillBlankCheckTests {
    let now = TestDate.at(2026, 11, 5)
    let engine: LearningEngine

    init() throws {
        let container = try ModelContainer(
            for: AppModel.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        engine = LearningEngine(context: ModelContext(container))
    }

    private func entry(_ id: String, _ word: String) -> WordEntry {
        WordEntry(
            id: id, word: word, pos: .adverb, level: nil, meaning: "\(word) の意味",
            example: "", exampleJa: ""
        )
    }

    private var moreover: WordEntry { entry("c-1", "moreover") }
    private var besides: WordEntry { entry("c-2", "besides") }
    private var however: WordEntry { entry("c-3", "however") }
    private var unless: WordEntry { entry("c-4", "unless") }

    private let passage = Passage(
        text: "This apartment is near the station. Moreover, the rent is low, so I want to live here.",
        ja: "このアパートは駅に近い。そのうえ家賃も安いので、ここに住みたい。"
    )

    /// moreover の穴埋め 1 問（選択肢の並び: moreover・besides・however・unless）
    private func quiz(alsoCorrect: Set<String> = []) -> Quiz {
        Quiz(
            word: moreover, type: .fillBlank, choices: [moreover, besides, however, unless],
            blankedExample: QuizBuilder.blank(passage.text, headword: "moreover"), passage: passage,
            alsoCorrectWordIds: alsoCorrect
        )
    }

    // MARK: - Quiz

    @Test("ほかにも正解の語を選んでも正解。出題した語は ほかの正解 に入れない")
    func quizAcceptsAlsoCorrect() {
        let quiz = quiz(alsoCorrect: ["c-2", "c-1"])
        #expect(quiz.isCorrect(choiceIndex: 0))
        #expect(quiz.isCorrect(choiceIndex: 1))
        #expect(!quiz.isCorrect(choiceIndex: 2))
        #expect(!quiz.isCorrect(choiceIndex: 9))
        #expect(quiz.alsoCorrectWordIds == ["c-2"])
        #expect(quiz.alsoCorrectChoices.map(\.word) == ["besides"])
    }

    // MARK: - 送る問題と結果の当てはめ

    @Test("判定に送るのは、空欄にした元の文・出題した語・誤答肢の綴り")
    func itemsForQuizzes() {
        let enToJa = Quiz(word: moreover, type: .enToJa, choices: [moreover, besides], blankedExample: nil)
        let items = FillBlankCheck.items(for: [enToJa, quiz()])
        #expect(items == [
            FillBlankCheckAPI.Item(
                id: "1", text: passage.text, answer: "moreover", choices: ["besides", "however", "unless"]
            ),
        ])
    }

    @Test("例文で出した問題は例文を送る")
    func itemsUseExampleWithoutPassage() {
        let word = WordEntry(
            id: "c-9", word: "however", pos: .adverb, level: nil, meaning: "しかし",
            example: "It was sunny. However, it was cold.", exampleJa: ""
        )
        let quiz = Quiz(
            word: word, type: .fillBlank, choices: [word, besides],
            blankedExample: QuizBuilder.blank(word.example, headword: word.word)
        )
        #expect(FillBlankCheck.items(for: [quiz]).first?.text == "It was sunny. However, it was cold.")
    }

    @Test("結果の綴りから誤答肢の語を引いて、ほかの正解に入れる（大文字・空白の違いは無視）")
    func applyResults() {
        let applied = FillBlankCheck.apply(
            [
                FillBlankCheckAPI.Result(id: "0", alsoCorrect: [" Besides"]),
                FillBlankCheckAPI.Result(id: "7", alsoCorrect: ["x"]),
            ],
            to: [quiz()]
        )
        #expect(applied[0].alsoCorrectWordIds == ["c-2"])
    }

    @Test("判定して、ほかにも正解の語を問題に入れる")
    func runAddsAlsoCorrect() async {
        let checker = FakeChecker(alsoCorrect: ["besides"])
        let checked = await FillBlankCheck.run([quiz()], checker: checker)
        #expect(checked[0].alsoCorrectWordIds == ["c-2"])
        #expect(checker.calls.count == 1)
    }

    @Test("10 問ずつに分けて送る")
    func runSplitsIntoChunks() async {
        let checker = FakeChecker()
        _ = await FillBlankCheck.run(Array(repeating: quiz(), count: 23), checker: checker)
        #expect(checker.calls.map(\.count).sorted() == [3, 10, 10])
    }

    @Test("判定に失敗したら、問題はそのまま（正解は出題した語だけ）")
    func runKeepsQuizzesOnFailure() async {
        let checked = await FillBlankCheck.run([quiz()], checker: FakeChecker(error: WordAssistError.offline))
        #expect(checked[0].alsoCorrectWordIds.isEmpty)
        #expect(!checked[0].isCorrect(choiceIndex: 1))
    }

    // MARK: - 組み立て済みの問題のドリル

    private func runner(_ quizzes: [Quiz]) -> SessionRunner {
        SessionRunner(drillQuizzes: quizzes, engine: engine, rng: SeededRNG(seed: 3), clock: { now })
    }

    private func currentQuiz(_ runner: SessionRunner) throws -> Quiz {
        guard case .quiz(let quiz, _) = runner.step else {
            Issue.record("クイズではなく \(runner.step) が表示されている")
            throw CancellationError()
        }
        return quiz
    }

    @Test("ほかにも正解の語を選ぶと正解になり、再出題しない")
    func drillAcceptsAlsoCorrect() throws {
        let runner = runner([quiz(alsoCorrect: ["c-2"])])
        let shown = try currentQuiz(runner)
        runner.answer(choiceIndex: try #require(shown.choices.firstIndex(of: besides)))
        #expect(runner.lastAnswerWasCorrect == true)
        #expect(runner.stats.correct == 1)
        runner.next()
        #expect(runner.isFinished)
    }

    @Test("間違えたら、同じ問題（同じ文章・同じ選択肢・同じほかの正解）を再出題する")
    func drillRequeuesSameQuiz() throws {
        let original = quiz(alsoCorrect: ["c-2"])
        let runner = runner([original])
        let first = try currentQuiz(runner)
        runner.answer(choiceIndex: try #require(first.choices.firstIndex(of: however)))
        #expect(runner.lastAnswerWasCorrect == false)
        runner.next()

        let again = try currentQuiz(runner)
        #expect(again.id != first.id)
        #expect(again.passage == original.passage)
        #expect(again.blankedExample == original.blankedExample)
        #expect(Set(again.choices.map(\.id)) == Set(original.choices.map(\.id)))
        #expect(again.alsoCorrectWordIds == ["c-2"])
        if case .quiz(_, let kind) = runner.step { #expect(kind == .requeue) }
    }

    @Test("組み立て済みの問題のドリルは、渡した順に出して締めに進む")
    func drillRunsInOrder() throws {
        let second = Quiz(
            word: however, type: .fillBlank, choices: [however, unless, besides, moreover],
            blankedExample: "It was sunny. ＿＿＿＿, it was cold."
        )
        let runner = runner([quiz(), second])
        #expect(try currentQuiz(runner).word == moreover)
        runner.answer(choiceIndex: try currentQuiz(runner).answerIndex)
        runner.next()
        #expect(try currentQuiz(runner).word == however)
        runner.answer(choiceIndex: try currentQuiz(runner).answerIndex)
        runner.next()
        #expect(runner.isFinished)
        #expect(runner.mode == .drill)
    }
}
