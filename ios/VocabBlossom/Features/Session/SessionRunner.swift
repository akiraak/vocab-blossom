import Foundation
import Observation

/// セッションの進行役。
///
/// 「復習 → 新規学習（5 語ミニバッチで提示 → 直後クイズ）→ 再出題 → 締め」の一本道を
/// キューとして持ち、回答のたびに即保存する（中断してもやり直しにならない）。
@Observable
final class SessionRunner {
    /// キューに積む単位。実際のクイズは表示直前に組み立てる
    /// （再出題では選択肢を作り直し、下がったステージも反映されるようにするため）
    enum Item: Equatable {
        case present(wordId: String)
        case quiz(wordId: String, kind: AnswerKind)
    }

    /// 画面に出す状態
    enum Step: Identifiable {
        case present(WordEntry)
        case quiz(Quiz, kind: AnswerKind)
        case summary

        var id: String {
            switch self {
            case .present(let word): "present-\(word.id)"
            case .quiz(let quiz, _): "quiz-\(quiz.id)"
            case .summary: "summary"
            }
        }
    }

    struct Stats: Equatable {
        var answered = 0
        var correct = 0
        /// 今回新しく学習した語
        var learnedWordIds: [String] = []
        /// 今回「開花」に到達した語
        var blossomedWordIds: [String] = []
        /// 「もう知ってる」で飛ばした語
        var knownWordIds: [String] = []

        var accuracy: Double? {
            answered > 0 ? Double(correct) / Double(answered) : nil
        }
    }

    private(set) var step: Step = .summary
    private(set) var stats = Stats()
    /// 回答済みなら選んだ選択肢の位置。未回答は nil
    private(set) var selectedIndex: Int?

    private var queue: [Item]
    private var requeueCounts: [String: Int] = [:]
    private var completed = 0

    private let engine: LearningEngine
    private let store: WordStore
    private var builder: QuizBuilder
    private let clock: () -> Date

    init(
        plan: SessionPlan,
        engine: LearningEngine,
        store: WordStore = .shared,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        clock: @escaping () -> Date = { .now }
    ) {
        self.engine = engine
        self.store = store
        self.clock = clock
        builder = QuizBuilder(store: store, rng: rng)

        var items: [Item] = plan.reviewWordIds.map { .quiz(wordId: $0, kind: .review) }
        // 新規学習は 5 語ずつ「まとめて提示 → まとめて直後クイズ」
        for batch in plan.newBatches {
            items.append(contentsOf: batch.map { .present(wordId: $0) })
            items.append(contentsOf: batch.map { .quiz(wordId: $0, kind: .new) })
        }
        queue = items
        advance()
    }

    // MARK: - 進行状況

    var isFinished: Bool {
        if case .summary = step { return true }
        return false
    }

    /// 進捗バー用の 0〜1
    var progress: Double {
        let total = completed + queue.count + (isFinished ? 0 : 1)
        guard total > 0 else { return 1 }
        return Double(completed) / Double(total)
    }

    /// 残りの問題数（提示カードは数えない）
    var remainingCount: Int {
        let pending = queue.count { if case .quiz = $0 { true } else { false } }
        if case .quiz = step { return pending + 1 }
        return pending
    }

    /// 回答後の正誤。未回答は nil
    var lastAnswerWasCorrect: Bool? {
        guard let selectedIndex, case .quiz(let quiz, _) = step else { return nil }
        return selectedIndex == quiz.answerIndex
    }

    // MARK: - 操作

    /// 4 択を選ぶ。同じ問題への 2 回目以降の選択は無視する
    func answer(choiceIndex: Int) {
        guard selectedIndex == nil, case .quiz(let quiz, let kind) = step else { return }
        selectedIndex = choiceIndex

        let wordId = quiz.word.id
        let correct = choiceIndex == quiz.answerIndex
        let previousStage = engine.progress(for: wordId)?.stage ?? 0
        let stageAfter = engine.record(
            wordId: wordId,
            correct: correct,
            quizType: quiz.type,
            kind: kind,
            now: clock()
        )

        stats.answered += 1
        if correct { stats.correct += 1 }
        if kind == .new, !stats.learnedWordIds.contains(wordId) {
            stats.learnedWordIds.append(wordId)
        }
        if previousStage < SRS.maxStage, stageAfter >= SRS.maxStage,
           !stats.blossomedWordIds.contains(wordId) {
            stats.blossomedWordIds.append(wordId)
        }

        // 間違えたカードはセッションの最後にもう一度（同一カード 2 回まで）
        if !correct {
            let used = requeueCounts[wordId, default: 0]
            if used < SRS.maxRequeue {
                requeueCounts[wordId] = used + 1
                queue.append(.quiz(wordId: wordId, kind: .requeue))
            }
        }
    }

    /// 「もう知ってる」。直後クイズを飛ばして次へ進む
    func markKnown() {
        guard case .present(let word) = step else { return }
        engine.markKnown(wordId: word.id, now: clock())
        queue.removeAll { $0 == .quiz(wordId: word.id, kind: .new) }
        if !stats.knownWordIds.contains(word.id) {
            stats.knownWordIds.append(word.id)
        }
        next()
    }

    /// 次のステップへ
    func next() {
        guard !isFinished else { return }
        completed += 1
        selectedIndex = nil
        advance()
    }

    private func advance() {
        while let item = queue.first {
            queue.removeFirst()
            if let step = resolve(item) {
                self.step = step
                return
            }
            // 単語が見つからない（データ不整合）ときは飛ばす
        }
        step = .summary
    }

    private func resolve(_ item: Item) -> Step? {
        switch item {
        case .present(let wordId):
            return store.word(id: wordId).map { Step.present($0) }
        case .quiz(let wordId, let kind):
            guard let word = store.word(id: wordId) else { return nil }
            let stage = engine.progress(for: wordId)?.stage ?? 0
            // 新規学習の直後クイズは必ず英→日から始める
            let type: QuizType = kind == .new ? .enToJa : SRS.quizType(for: stage)
            return .quiz(builder.make(for: word, type: type), kind: kind)
        }
    }
}
