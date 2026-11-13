import Foundation
import Observation

/// セッションの進行役。
///
/// 「復習 → 新規学習（5 語ミニバッチで提示 → 直後クイズ）→ 再出題 → 締め」の一本道を
/// キューとして持ち、回答のたびに即保存する（中断してもやり直しにならない）。
///
/// ドリル（`Mode.drill`）は「全語クイズ → 再出題 → 締め」だけで、進捗も回答ログも残さない。
/// 形式を固定したドリル（穴埋めモードなど）も同じ流れ。
///
/// グループから始めたとき（`group` を渡したとき）は、どのモードでも回答を `GroupAnswerLog` に残す
/// （グループ一覧の回答数・達成度に使う）。
@Observable
final class SessionRunner {
    enum Mode: Equatable {
        /// いつもの学習。回答を SRS に記録する
        case learning
        /// グループのドリル。SRS の進捗・ログを動かさない練習
        case drill
    }

    /// キューに積む単位。実際のクイズは表示直前に組み立てる
    /// （再出題では選択肢を作り直し、下がったステージも反映されるようにするため）
    enum Item: Equatable {
        case present(wordId: String)
        case quiz(wordId: String, kind: AnswerKind)
        /// 組み立て済みの問題（`preparedQuizzes` の位置）。再出題でも同じ問題を選択肢の並びだけ変えて出す
        case prepared(index: Int, kind: AnswerKind)
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
        /// 1 回でも間違えた語（ドリルの締めで見直す）
        var missedWordIds: [String] = []

        var accuracy: Double? {
            answered > 0 ? Double(correct) / Double(answered) : nil
        }
    }

    let mode: Mode
    /// グループから始めたときの入口。nil（毎日の学習など）なら `GroupAnswerLog` に残さない
    let group: GroupAnswerContext?
    /// ドリルで固定する出題形式。nil ならステージで決める
    let drillQuizType: QuizType?
    private(set) var step: Step = .summary
    private(set) var stats = Stats()
    /// 4 択で回答済みなら選んだ選択肢の位置。未回答・入力の問題は nil
    private(set) var selectedIndex: Int?
    /// 入力の問題で回答済みなら打った綴り（「わからない」は空）。未回答・4 択は nil
    private(set) var typedAnswer: String?

    /// 今の問題に答えたか（4 択・入力のどちらでも）
    var isAnswered: Bool { selectedIndex != nil || typedAnswer != nil }

    private var queue: [Item]
    /// 表示中のステップの元になったキューの項目
    private var currentItem: Item?
    /// 組み立て済みの問題（グループの穴埋めモード。選択肢を AI で判定してある）
    private let preparedQuizzes: [Quiz]
    private var requeueCounts: [String: Int] = [:]
    private var completed = 0

    private let engine: LearningEngine
    private let store: WordStore
    private var builder: QuizBuilder
    /// 穴埋めで出した文章を残す先（次は別の文章を出すため）。nil なら残さない
    private let passageHistory: PassageHistory?
    private let clock: () -> Date

    init(
        plan: SessionPlan,
        engine: LearningEngine,
        store: WordStore = .shared,
        groups: [QuizGroup] = [],
        passages: @escaping PassageLookup = Passages.none,
        passageHistory: PassageHistory? = nil,
        group: GroupAnswerContext? = nil,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        clock: @escaping () -> Date = { .now }
    ) {
        self.engine = engine
        self.store = store
        self.clock = clock
        self.group = group
        mode = .learning
        drillQuizType = nil
        preparedQuizzes = []
        self.passageHistory = passageHistory
        builder = QuizBuilder(
            store: store, groups: groups, passages: passages, passageHistory: passageHistory, rng: rng
        )

        var items: [Item] = plan.reviewWordIds.map { .quiz(wordId: $0, kind: .review) }
        // 新規学習は 5 語ずつ「まとめて提示 → まとめて直後クイズ」
        for batch in plan.newBatches {
            items.append(contentsOf: batch.map { .present(wordId: $0) })
            items.append(contentsOf: batch.map { .quiz(wordId: $0, kind: .new) })
        }
        queue = items
        advance()
    }

    /// ドリル。渡した順にすべてクイズで出す（並びは呼び出し側でシャッフルしておく）。
    ///
    /// `quizType` を渡すと、再出題も含めてその形式で出す（穴埋めモード）。
    /// 穴埋めにできない語は `QuizBuilder` が英→日にするので、呼び出し側で `QuizBuilder.canFillBlank` で絞っておく
    init(
        drillWordIds: [String],
        quizType: QuizType? = nil,
        engine: LearningEngine,
        store: WordStore = .shared,
        groups: [QuizGroup] = [],
        passages: @escaping PassageLookup = Passages.none,
        passageHistory: PassageHistory? = nil,
        group: GroupAnswerContext? = nil,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        clock: @escaping () -> Date = { .now }
    ) {
        self.engine = engine
        self.store = store
        self.clock = clock
        self.group = group
        mode = .drill
        drillQuizType = quizType
        preparedQuizzes = []
        self.passageHistory = passageHistory
        builder = QuizBuilder(
            store: store, groups: groups, passages: passages, passageHistory: passageHistory, rng: rng
        )
        queue = drillWordIds.map { .quiz(wordId: $0, kind: .review) }
        advance()
    }

    /// 組み立て済みの問題で進めるドリル（グループの穴埋めモード）。渡した順に出す。
    ///
    /// 選択肢を AI で判定してあるので、間違えた語の再出題も作り直さず、同じ問題を選択肢の並びだけ変えて出す
    init(
        drillQuizzes: [Quiz],
        engine: LearningEngine,
        store: WordStore = .shared,
        passageHistory: PassageHistory? = nil,
        group: GroupAnswerContext? = nil,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        clock: @escaping () -> Date = { .now }
    ) {
        self.engine = engine
        self.store = store
        self.clock = clock
        self.group = group
        self.passageHistory = passageHistory
        mode = .drill
        drillQuizType = drillQuizzes.first?.type
        preparedQuizzes = drillQuizzes
        builder = QuizBuilder(store: store, rng: rng)
        queue = drillQuizzes.indices.map { .prepared(index: $0, kind: .review) }
        advance()
    }

    // MARK: - 進行状況

    /// このあと出す語（キューの先頭から、同じ語を除いて最大 `limit` 語）。読み上げの先読みに使う
    func upcomingWords(limit: Int) -> [WordEntry] {
        var seen = Set<String>()
        var words: [WordEntry] = []
        for item in queue {
            guard words.count < limit else { break }
            let word: WordEntry?
            switch item {
            case .present(let wordId), .quiz(let wordId, _):
                word = store.word(id: wordId)
            case .prepared(let index, _):
                word = preparedQuizzes.indices.contains(index) ? preparedQuizzes[index].word : nil
            }
            guard let word, seen.insert(word.id).inserted else { continue }
            words.append(word)
        }
        return words
    }

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
        let pending = queue.count { if case .present = $0 { false } else { true } }
        if case .quiz = step { return pending + 1 }
        return pending
    }

    /// 回答後の正誤。未回答は nil
    var lastAnswerWasCorrect: Bool? {
        guard case .quiz(let quiz, _) = step else { return nil }
        if let typedAnswer { return quiz.isCorrect(typed: typedAnswer) }
        return selectedIndex.map { quiz.isCorrect(choiceIndex: $0) }
    }

    // MARK: - 操作

    /// 4 択を選ぶ。同じ問題への 2 回目以降の選択は無視する
    func answer(choiceIndex: Int) {
        guard !isAnswered, case .quiz(let quiz, let kind) = step, quiz.input == .choice else { return }
        selectedIndex = choiceIndex
        // ほかにも正解の語（AI の判定。グループの穴埋めモードだけ）を選んでも正解
        record(quiz, kind: kind, correct: quiz.isCorrect(choiceIndex: choiceIndex))
    }

    /// 入力の問題に、打った綴りで答える（「わからない」は空で答える = 不正解）。2 回目以降は無視する
    func answer(text: String) {
        guard !isAnswered, case .quiz(let quiz, let kind) = step, quiz.input == .typing else { return }
        typedAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        record(quiz, kind: kind, correct: quiz.isCorrect(typed: text))
    }

    /// 回答を数え、記録し、間違えたら再出題に積む（4 択・入力で同じ）
    private func record(_ quiz: Quiz, kind: AnswerKind, correct: Bool) {
        let wordId = quiz.word.id

        stats.answered += 1
        if correct { stats.correct += 1 }
        if !correct, !stats.missedWordIds.contains(wordId) {
            stats.missedWordIds.append(wordId)
        }

        recordPassage(of: quiz)

        if let group {
            engine.recordGroupAnswer(
                group, wordId: wordId, correct: correct, quizType: quiz.type, kind: kind, now: clock()
            )
        }

        if mode == .learning {
            let previousStage = engine.progress(for: wordId)?.stage ?? 0
            let stageAfter = engine.record(
                wordId: wordId,
                correct: correct,
                quizType: quiz.type,
                kind: kind,
                now: clock()
            )
            if kind == .new, !stats.learnedWordIds.contains(wordId) {
                stats.learnedWordIds.append(wordId)
            }
            if previousStage < SRS.maxStage, stageAfter >= SRS.maxStage,
               !stats.blossomedWordIds.contains(wordId) {
                stats.blossomedWordIds.append(wordId)
            }
        }

        // 間違えたカードはセッションの最後にもう一度（同一カード 2 回まで）
        if !correct {
            let used = requeueCounts[wordId, default: 0]
            if used < SRS.maxRequeue {
                requeueCounts[wordId] = used + 1
                if case .prepared(let index, _) = currentItem {
                    queue.append(.prepared(index: index, kind: .requeue))
                } else {
                    queue.append(.quiz(wordId: wordId, kind: .requeue))
                }
            }
        }
    }

    /// 穴埋めで出した文章を残し、次にこの語を出すときは別の文章にする
    private func recordPassage(of quiz: Quiz) {
        guard let passageIndex = quiz.passageIndex else { return }
        passageHistory?.markShown(word: quiz.word.word, sense: quiz.sense, index: passageIndex)
    }

    /// 「もう知ってる」。直後クイズを飛ばして次へ進む
    func markKnown() {
        guard mode == .learning, case .present(let word) = step else { return }
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
        typedAnswer = nil
        advance()
    }

    private func advance() {
        while let item = queue.first {
            queue.removeFirst()
            if let step = resolve(item) {
                self.step = step
                currentItem = item
                return
            }
            // 単語が見つからない（データ不整合）ときは飛ばす
        }
        step = .summary
        currentItem = nil
    }

    private func resolve(_ item: Item) -> Step? {
        switch item {
        case .present(let wordId):
            return store.word(id: wordId).map { Step.present($0) }
        case .quiz(let wordId, let kind):
            guard let word = store.word(id: wordId) else { return nil }
            let stage = engine.progress(for: wordId)?.stage ?? 0
            // 新規学習の直後クイズは必ず英→日から始める。形式を固定したドリルはその形式
            let type: QuizType = drillQuizType ?? (kind == .new ? .enToJa : SRS.quizType(for: stage))
            return .quiz(builder.make(for: word, type: type), kind: kind)
        case .prepared(let index, let kind):
            guard preparedQuizzes.indices.contains(index) else { return nil }
            let quiz = preparedQuizzes[index]
            // 再出題は選択肢の並びを変える（Quiz の id も変わり、画面が新しい問題として出す）
            return .quiz(kind == .requeue ? builder.reshuffle(quiz) : quiz, kind: kind)
        }
    }
}
