import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

nonisolated private let config = ServerConfig(
    baseURL: URL(string: "https://vocab.example.com")!, apiKey: "secret"
)

/// commute（動詞: 通勤する／名詞: 通勤）。例文はどちらも空欄にできない
nonisolated private let commute = WordEntry(
    id: "custom-commute", word: "commute", pos: .verb, level: nil, meaning: "通勤する",
    example: "I go by bus.", exampleJa: "",
    extraSenses: [WordSense(pos: .noun, meaning: "通勤", example: "The trip is long.")]
)

nonisolated private func passages(_ word: String, _ count: Int = 3) -> [Passage] {
    (1...count).map { Passage(text: "Story \($0). I \(word) every day, so I am tired.", ja: "話 \($0)。") }
}

@Suite("穴埋めの文章: 出題")
struct PassageQuizTests {
    let store = WordStore.shared

    private func word(_ id: String) throws -> WordEntry {
        try #require(store.word(id: id))
    }

    @Test("文章があれば例文より優先し、空欄にした文章と元の文章を持つ")
    func usesPassages() throws {
        let target = try word("a1-0004")  // action: He is a man of action.
        let text = "Tom never waits. He is a man of action, so he starts work at once."
        let lookup: PassageLookup = { entry, _ in
            entry.id == "a1-0004" ? [Passage(text: text, ja: "トムは待たない。")] : []
        }
        var builder = QuizBuilder(store: store, passages: lookup, rng: SeededRNG(seed: 3))
        let quiz = builder.make(for: target, type: .fillBlank)
        #expect(quiz.type == .fillBlank)
        #expect(quiz.passage?.text == text)
        let expected = "Tom never waits. He is a man of \(Quiz.blankPlaceholder), so he starts work at once."
        #expect(quiz.blankedExample == expected)
    }

    @Test("空欄にできない文章は使わず、例文で出す")
    func skipsUnblankablePassages() throws {
        let target = try word("a1-0004")
        let lookup: PassageLookup = { _, _ in [Passage(text: "No headword here at all.", ja: "なし。")] }
        var builder = QuizBuilder(store: store, passages: lookup, rng: SeededRNG(seed: 3))
        let quiz = builder.make(for: target, type: .fillBlank)
        #expect(quiz.type == .fillBlank)
        #expect(quiz.passage == nil)
        #expect(quiz.blankedExample?.hasPrefix("He is a man of") == true)
    }

    @Test("意味ごとの文章から選び、出題する意味はその文章の意味にする")
    func passagesPerSense() {
        let lookup: PassageLookup = { _, sense in
            let text = "The trains are full. My commute is long and tiring."
            return sense.pos == .noun ? [Passage(text: text, ja: "通勤。")] : []
        }
        let store = store.including(customWords: [commute])
        for seed in 1...5 {
            var builder = QuizBuilder(store: store, passages: lookup, rng: SeededRNG(seed: UInt64(seed)))
            let quiz = builder.make(for: commute, type: .fillBlank)
            #expect(quiz.type == .fillBlank)
            #expect(quiz.sense.pos == .noun)
            #expect(quiz.passage != nil)
        }
    }

    @Test("例文で空欄にできなくても、文章があれば穴埋めで出せる")
    func canFillBlankWithPassages() {
        #expect(!QuizBuilder.canFillBlank(commute))
        #expect(QuizBuilder.canFillBlank(commute) { _, _ in passages("commute") })
        #expect(!QuizBuilder.canFillBlank(commute) { _, _ in [Passage(text: "Nothing here.", ja: "なし。")] })
    }
}

@Suite("穴埋めの文章: 順番に出す")
struct PassageRotationTests {
    /// commute の動詞の意味だけに 3 パターンの文章がある（2 つ目は空欄にできない）
    private let lookup: PassageLookup = { _, sense in
        guard sense.pos == .verb else { return [] }
        var items = passages("commute")
        items[1] = Passage(text: "Nothing here. No headword at all.", ja: "なし。")
        return items
    }

    private var store: WordStore { WordStore.shared.including(customWords: [commute]) }

    private func make(history: PassageHistory?) -> Quiz {
        var builder = QuizBuilder(
            store: store, passages: lookup, passageHistory: history, rng: SeededRNG(seed: 1)
        )
        return builder.make(for: commute, type: .fillBlank)
    }

    @Test("出したことが無ければ 1 つ目、残すたびに次の文章（空欄にできないものは飛ばし、最後の次は最初）")
    func rotates() {
        let history = PassageHistory(fileURL: nil)
        var shown: [Int?] = []
        for _ in 0..<4 {
            let quiz = make(history: history)
            shown.append(quiz.passageIndex)
            #expect(quiz.passage == quiz.passageIndex.map { lookup(commute, commute.primarySense)[$0] })
            if let index = quiz.passageIndex {
                history.markShown(word: commute.word, sense: quiz.sense, index: index)
            }
        }
        #expect(shown == [0, 2, 0, 2])
    }

    @Test("残さなければ毎回同じ文章、履歴が無ければ 1 つ目")
    func withoutHistory() {
        let history = PassageHistory(fileURL: nil)
        #expect(make(history: history).passageIndex == 0)
        #expect(make(history: history).passageIndex == 0)
        #expect(make(history: nil).passageIndex == 0)
    }

    @Test("文章の数より大きい位置が残っていても、最初に戻って出す")
    func outOfRangeHistory() {
        let history = PassageHistory(fileURL: nil)
        history.markShown(word: commute.word, sense: commute.primarySense, index: 7)
        #expect(make(history: history).passageIndex == 2)  // (7 + 1) % 3 = 2
    }

    @Test("例文で出した問題は位置を持たない")
    func exampleHasNoIndex() throws {
        let target = try #require(WordStore.shared.word(id: "a1-0004"))
        var builder = QuizBuilder(
            store: .shared, passageHistory: PassageHistory(fileURL: nil), rng: SeededRNG(seed: 1)
        )
        let quiz = builder.make(for: target, type: .fillBlank)
        #expect(quiz.passage == nil)
        #expect(quiz.passageIndex == nil)
    }

    @Test("回答すると出した文章の位置が残り、次のセッションでは次の文章が出る")
    func runnerRecordsOnAnswer() throws {
        let container = try ModelContainer(
            for: AppModel.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let engine = LearningEngine(context: ModelContext(container))
        let history = PassageHistory(fileURL: nil)
        let store = store

        func runOnce() throws -> Int? {
            let runner = SessionRunner(
                drillWordIds: [commute.id], quizType: .fillBlank, engine: engine, store: store,
                passages: lookup, passageHistory: history, rng: SeededRNG(seed: 1)
            )
            guard case .quiz(let quiz, _) = runner.step else {
                Issue.record("クイズが出ていない")
                return nil
            }
            #expect(history.lastShownIndex(word: commute.word, sense: quiz.sense) != quiz.passageIndex
                || quiz.passageIndex == nil)
            runner.answer(choiceIndex: quiz.answerIndex)
            #expect(history.lastShownIndex(word: commute.word, sense: quiz.sense) == quiz.passageIndex)
            return quiz.passageIndex
        }

        #expect(try runOnce() == 0)
        #expect(try runOnce() == 2)
    }
}

@Suite("穴埋めの文章: 出した文章の履歴")
struct PassageHistoryTests {
    @Test("残した位置は保存され、開き直しても残っている")
    func persists() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "passage-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let sense = commute.primarySense

        let history = PassageHistory(fileURL: url)
        #expect(history.lastShownIndex(word: "commute", sense: sense) == nil)
        history.markShown(word: "Commute", sense: sense, index: 1)

        let reopened = PassageHistory(fileURL: url)
        #expect(reopened.lastShownIndex(word: "commute", sense: sense) == 1)
        #expect(reopened.lastShownIndex(word: "commute", sense: commute.senses[1]) == nil)
    }
}

@Suite("穴埋めの文章: 端末のキャッシュ")
struct PassageCacheTests {
    @Test("鍵は綴り（大小文字は区別しない）・品詞・意味。意味を直すと別の鍵")
    func keys() {
        let sense = WordSense(pos: .verb, meaning: "通勤する")
        #expect(Passages.key(word: " Commute ", sense: sense) == "commute\tverb\t通勤する")
        #expect(Passages.key(word: "commute", sense: WordSense(pos: .verb, meaning: "通う"))
            != Passages.key(word: "commute", sense: sense))
    }

    @Test("ためた文章をファイルに書き、開き直しても読める。空の文章は入れない")
    func persists() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "passages-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let sense = WordSense(pos: .verb, meaning: "通勤する")
        let cache = PassageCache(fileURL: url)
        cache.store([
            Passages.key(word: "commute", sense: sense): passages("commute"),
            Passages.key(word: "walk", sense: WordSense(pos: .verb, meaning: "歩く")): [],
        ])
        #expect(cache.contains(word: "Commute", sense: sense))

        let reopened = PassageCache(fileURL: url)
        #expect(reopened.passages(word: "commute", sense: sense) == passages("commute"))
        #expect(!reopened.contains(word: "walk", sense: WordSense(pos: .verb, meaning: "歩く")))
    }
}

/// 呼ばれた語を記録し、決めた返事を返す偽物
private final class FakeFetcher: PassageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String]] = []
    private var refreshes: [Bool] = []
    let respond: @Sendable ([PassageAPI.Word]) throws -> [PassageAPI.Result]

    init(respond: @escaping @Sendable ([PassageAPI.Word]) throws -> [PassageAPI.Result]) {
        self.respond = respond
    }

    var recordedCalls: [[String]] { lock.withLock { calls } }

    var recordedRefreshes: [Bool] { lock.withLock { refreshes } }

    func fetch(_ words: [PassageAPI.Word], refresh: Bool) async throws -> [PassageAPI.Result] {
        lock.withLock {
            calls.append(words.map(\.id))
            refreshes.append(refresh)
        }
        return try respond(words)
    }
}

@Suite("穴埋め: キーボードで入力")
struct TypingQuizTests {
    let store = WordStore.shared

    private func custom(_ word: String, example: String = "") -> WordEntry {
        WordEntry(
            id: "custom-\(word)", word: word, pos: .verb, level: nil, meaning: "意味", example: example,
            exampleJa: ""
        )
    }

    private let adaptText = "Mia moved to Japan. She adapted quickly to her new school."

    private func typingQuiz(_ word: WordEntry, text: String) -> Quiz {
        let lookup: PassageLookup = { entry, _ in
            entry.id == word.id ? [Passage(text: text, ja: "訳。")] : []
        }
        var builder = QuizBuilder(store: store, passages: lookup, rng: SeededRNG(seed: 1))
        return builder.make(for: word, type: .fillBlank, input: .typing)
    }

    @Test("入力の問題は選択肢を持たず、正解は文中で空欄にした形")
    func surfaceFormIsAnswer() {
        let quiz = typingQuiz(custom("adapt"), text: adaptText)
        #expect(quiz.type == .fillBlank)
        #expect(quiz.input == .typing)
        #expect(quiz.choices.isEmpty)
        #expect(quiz.typedAnswer == "adapted")
        let blanked = adaptText.replacingOccurrences(of: "adapted", with: Quiz.blankPlaceholder)
        #expect(quiz.blankedExample == blanked)
        #expect(quiz.passageIndex == 0)
        // 選択肢が無いので、AI の判定には送らない
        #expect(FillBlankCheck.items(for: [quiz]).isEmpty)
    }

    @Test("大文字小文字・空白・アポストロフィの違いは正解。綴り違い・活用違い・空は不正解")
    func judgesTyped() {
        let quiz = typingQuiz(custom("adapt"), text: adaptText)
        #expect(quiz.isCorrect(typed: "adapted"))
        #expect(quiz.isCorrect(typed: "  Adapted "))
        #expect(!quiz.isCorrect(typed: "adapt"))
        #expect(!quiz.isCorrect(typed: "adaptid"))
        #expect(!quiz.isCorrect(typed: ""))
        #expect(!quiz.isCorrect(typed: "   "))
        // 見出し語を打って、文中の形と違うときだけ「この文では…」と添える
        #expect(quiz.isHeadwordInOtherForm(typed: "Adapt"))
        #expect(!quiz.isHeadwordInOtherForm(typed: "adapted"))
        #expect(!quiz.isHeadwordInOtherForm(typed: "adopt"))

        let phrase = typingQuiz(custom("point of view"), text: "I see. I understand your point of view.")
        #expect(phrase.typedAnswer == "point of view")
        #expect(phrase.isCorrect(typed: "Point  of   view"))
        #expect(!phrase.isCorrect(typed: "pointofview"))

        let apostrophe = typingQuiz(custom("can't wait"), text: "The trip is tomorrow. I can't wait to go.")
        #expect(apostrophe.isCorrect(typed: "can\u{2019}t wait"))
    }

    @Test("空欄が 2 か所の語は、空白で区切って打つ")
    func twoBlanks() {
        let quiz = typingQuiz(custom("either … or …"), text: "I am thirsty. Either tea or coffee is fine.")
        #expect(quiz.typedAnswer == "Either or")
        #expect(quiz.isCorrect(typed: "either or"))
        #expect(!quiz.isCorrect(typed: "either"))
    }

    @Test("文章が無ければ例文で出し、空欄にできない語は 4 択の英→日になる")
    func fallsBack() {
        var builder = QuizBuilder(store: store, rng: SeededRNG(seed: 1))
        let fromExample = builder.make(
            for: custom("adapt", example: "Cats adapt to new homes."), type: .fillBlank, input: .typing
        )
        #expect(fromExample.input == .typing)
        #expect(fromExample.typedAnswer == "adapt")
        #expect(fromExample.passage == nil)

        let noWord = custom("adapt", example: "No word here.")
        let notBlankable = builder.make(for: noWord, type: .fillBlank, input: .typing)
        #expect(notBlankable.type == .enToJa)
        #expect(notBlankable.input == .choice)
        #expect(notBlankable.typedAnswer == nil)
        #expect(notBlankable.choices.count == QuizBuilder.choiceCount)
    }

    @Test("再出題用に作り直しても、答え方と正解の綴りは変わらない")
    func keepsInputWhenReshuffled() {
        let quiz = typingQuiz(custom("adapt"), text: adaptText)
        var rng = SeededRNG(seed: 2)
        let again = quiz.reshuffled(using: &rng)
        #expect(again.id != quiz.id)
        #expect(again.input == .typing)
        #expect(again.typedAnswer == "adapted")
    }
}

@Suite("穴埋めの文章: 始める前に作る")
@MainActor
struct PassagePreparationTests {
    let store = WordStore.shared

    @Test("文章の無い語・意味だけを、意味ごとに 1 件で並べる")
    func missingWords() throws {
        let action = try #require(store.word(id: "a1-0004"))
        let cache = PassageCache(fileURL: nil)
        cache.store([Passages.key(word: "commute", sense: commute.primarySense): passages("commute")])

        let missing = PassagePreparation.missingWords([action, commute], cache: cache)
        #expect(missing.map(\.id) == ["a1-0004#0", "custom-commute#1"])
        #expect(missing[1].pos == .noun)
        #expect(missing[1].meaning == "通勤")
        #expect(missing[1].example == "The trip is long.")
    }

    @Test("3 語ずつ送り、返ってきた文章をためる。作れなかった語は failed で、ほかは続ける")
    func runsInChunks() async throws {
        let requests = (0..<7).map {
            PassageAPI.Word(id: "w\($0)", word: "word\($0)", pos: .noun, meaning: "意味\($0)", example: "")
        }
        let fetcher = FakeFetcher { words in
            words.map { PassageAPI.Result(id: $0.id, passages: $0.id == "w5" ? [] : passages($0.word)) }
        }
        let cache = PassageCache(fileURL: nil)
        let preparation = PassagePreparation(requests: requests)
        #expect(preparation.total == 7)
        #expect(preparation.doneCount == 0)

        await preparation.run(fetcher: fetcher, cache: cache)

        #expect(fetcher.recordedCalls.map(\.count).sorted() == [1, 3, 3])
        #expect(preparation.phase == .finished(failedCount: 1))
        #expect(preparation.doneCount == 7)
        #expect(preparation.items.first { $0.id == "w5" }?.state == .failed)
        #expect(cache.contains(word: "word0", sense: WordSense(pos: .noun, meaning: "意味0")))
        #expect(!cache.contains(word: "word5", sense: WordSense(pos: .noun, meaning: "意味5")))
    }

    @Test("すべて失敗したら failed にし、もう一度で作り直せる")
    func failsThenRetries() async {
        let requests = [PassageAPI.Word(id: "a#0", word: "apple", pos: .noun, meaning: "りんご", example: "")]
        let cache = PassageCache(fileURL: nil)
        let preparation = PassagePreparation(requests: requests)

        await preparation.run(fetcher: FakeFetcher { _ in throw WordAssistError.offline }, cache: cache)
        #expect(preparation.phase == .failed(message: WordAssistError.offline.localizedDescription))

        await preparation.run(fetcher: FakeFetcher { words in
            words.map { PassageAPI.Result(id: $0.id, passages: passages("apple")) }
        }, cache: cache)
        #expect(preparation.phase == .finished(failedCount: 0))
        #expect(preparation.items.map(\.state) == [.done])
    }

    @Test("作り直すときは文章のある語も全部送り、返った文章で上書きする。作り直せなかった語は前の文章が残る")
    func refreshesAll() async throws {
        let action = try #require(store.word(id: "a1-0004"))
        let cache = PassageCache(fileURL: nil)
        let old = passages("commute")
        cache.store([
            Passages.key(word: "commute", sense: commute.primarySense): old,
            Passages.key(word: "commute", sense: commute.senses[1]): old,
        ])
        let fresh = [Passage(text: "New story. I commute by train now.", ja: "新しい話。")]

        let requests = PassagePreparation.allWords([action, commute])
        #expect(requests.map(\.id) == ["a1-0004#0", "custom-commute#0", "custom-commute#1"])

        let fetcher = FakeFetcher { words in
            // 名詞の意味（#1）だけ作り直せなかった
            words.map { PassageAPI.Result(id: $0.id, passages: $0.id == "custom-commute#1" ? [] : fresh) }
        }
        let preparation = PassagePreparation(requests: requests, refresh: true)
        await preparation.run(fetcher: fetcher, cache: cache)

        #expect(fetcher.recordedRefreshes == [true])
        #expect(preparation.phase == .finished(failedCount: 1))
        #expect(cache.passages(word: "commute", sense: commute.primarySense) == fresh)
        #expect(cache.passages(word: "commute", sense: commute.senses[1]) == old)
        #expect(cache.passages(word: action.word, sense: action.primarySense) == fresh)
    }

    @Test("作り直さないときは refresh を付けない")
    func noRefreshByDefault() async {
        let requests = [PassageAPI.Word(id: "a#0", word: "apple", pos: .noun, meaning: "りんご", example: "")]
        let fetcher = FakeFetcher { words in
            words.map { PassageAPI.Result(id: $0.id, passages: passages("apple")) }
        }
        await PassagePreparation(requests: requests).run(fetcher: fetcher, cache: PassageCache(fileURL: nil))
        #expect(fetcher.recordedRefreshes == [false])
    }

    @Test("意味が複数ある語のチップには意味を添える")
    func detailForMultiSense() {
        let missing = PassagePreparation.missingWords([commute], cache: PassageCache(fileURL: nil))
        let preparation = PassagePreparation(requests: missing)
        #expect(preparation.items.map(\.detail) == ["通勤する", "通勤"])
    }
}

@Suite("穴埋めの文章: 通信")
struct PassageClientTests {
    @Test("Bearer つきで語を送り、文章を読み取る")
    func sendsAndDecodes() async throws {
        let sent = RequestCapture()
        let session = StubURLProtocol.session { request, body in
            sent.set(request, body)
            let body = #"{"results":[{"id":"a#0","passages":[{"text":"t","ja":"j"}]},"#
                + #"{"id":"b#0","passages":[]}]}"#
            return (200, Data(body.utf8))
        }
        let words = [
            PassageAPI.Word(id: "a#0", word: "apple", pos: .noun, meaning: "りんご", example: "I eat an apple."),
            PassageAPI.Word(id: "b#0", word: "run", pos: .verb, meaning: "走る", example: ""),
        ]
        let client = PassageClient(config: config, session: session, model: { .sonnet55 })
        let results = try await client.fetch(words, refresh: true)

        let (request, body) = try #require(sent.value)
        #expect(request.url?.absoluteString == "https://vocab.example.com/api/passages")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        struct SentBody: Decodable {
            var words: [PassageAPI.Word]
            var model: String
            var refresh: Bool
        }
        let sentBody = try JSONDecoder().decode(SentBody.self, from: body)
        #expect(sentBody.refresh)
        #expect(sentBody.words == words)
        #expect(sentBody.model == "claude-sonnet-5-5")
        #expect(results == [
            PassageAPI.Result(id: "a#0", passages: [Passage(text: "t", ja: "j")]),
            PassageAPI.Result(id: "b#0", passages: []),
        ])
    }

    @Test("状態コードは AI チェックと同じエラーに分ける")
    func mapsStatus() async {
        let session = StubURLProtocol.session { _, _ in (503, Data("{}".utf8)) }
        await #expect(throws: WordAssistError.unavailable) {
            _ = try await PassageClient(config: config, session: session).fetch([], refresh: false)
        }
    }
}
