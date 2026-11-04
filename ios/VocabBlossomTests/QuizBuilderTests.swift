import Foundation
import Testing

@testable import VocabBlossom

@Suite("クイズ生成")
struct QuizBuilderTests {
    let store = WordStore.shared

    private func builder(seed: UInt64 = 1) -> QuizBuilder {
        QuizBuilder(store: store, rng: SeededRNG(seed: seed))
    }

    private func word(_ id: String) throws -> WordEntry {
        try #require(store.word(id: id))
    }

    @Test("選択肢は 4 つで、正解をちょうど 1 つ含む")
    func fourChoicesWithOneAnswer() throws {
        var builder = builder()
        for id in ["a1-0001", "a1-0500", "a2-0100", "ph-0001"] {
            let quiz = builder.make(for: try word(id), type: .enToJa)
            #expect(quiz.choices.count == QuizBuilder.choiceCount)
            #expect(quiz.choices.filter { $0.id == quiz.word.id }.count == 1)
            #expect(Set(quiz.choices.map(\.meaning)).count == QuizBuilder.choiceCount)
            #expect(quiz.choices[quiz.answerIndex].id == quiz.word.id)
        }
    }

    @Test("誤答肢は同レベル・同品詞から選ばれる")
    func distractorsShareLevelAndPos() throws {
        var builder = builder(seed: 7)
        let target = try word("a1-0004")  // action / noun / A1
        for _ in 0..<20 {
            let quiz = builder.make(for: target, type: .enToJa)
            for choice in quiz.choices where choice.id != target.id {
                #expect(choice.level == target.level)
                #expect(choice.pos == target.pos)
            }
        }
    }

    @Test("同レベル・同品詞が足りないときは範囲を広げる")
    func distractorsFallBackWhenPoolIsSmall() throws {
        let target = WordEntry(
            id: "x-0001", word: "zzz", pos: .interjection, level: .a1,
            meaning: "ううん", example: "Zzz.", exampleJa: "ううん。"
        )
        let others = (1...5).map { index in
            WordEntry(
                id: "x-\(index + 1)", word: "w\(index)", pos: .noun, level: .a1,
                meaning: "意味\(index)", example: "W\(index).", exampleJa: "意味\(index)。"
            )
        }
        let small = WordStore(decks: [Deck(id: "x", name: "x", words: [target] + others)])
        var builder = QuizBuilder(store: small, rng: SeededRNG(seed: 3))
        let quiz = builder.make(for: target, type: .enToJa)
        #expect(quiz.choices.count == QuizBuilder.choiceCount)
        #expect(quiz.choices.contains(target))
    }

    @Test("同じ綴りの同梱語がある自作語でも、選択肢に同じ綴りが 2 つ並ばない")
    func sameSpellingIsNotADistractor() throws {
        let custom = WordEntry(
            id: "custom-1", word: " Action ", pos: .noun, level: nil, meaning: "アクション（映画）",
            example: "I like action movies.", exampleJa: "アクション映画が好きです。"
        )
        let store = store.including(customWords: [custom])
        for seed in 1...30 {
            var builder = QuizBuilder(store: store, rng: SeededRNG(seed: UInt64(seed)))
            for type in [QuizType.jaToEn, .fillBlank] {
                let quiz = builder.make(for: custom, type: type)
                let spellings = quiz.choices.map { WordStore.normalizedSpelling($0.word) }
                #expect(Set(spellings).count == QuizBuilder.choiceCount)
                #expect(!quiz.choices.contains { $0.id == "a1-0004" })
            }
        }
    }

    @Test("同梱データの全語で、誤答肢どうしも綴り・意味が重ならない")
    func distractorsAreDistinctOnBundledData() {
        var builder = builder(seed: 11)
        for word in store.allWords {
            let choices = builder.distractors(for: word) + [word]
            #expect(choices.count == QuizBuilder.choiceCount)
            #expect(Set(choices.map { WordStore.normalizedSpelling($0.word) }).count == choices.count)
            #expect(Set(choices.map(\.meaning)).count == choices.count)
        }
    }

    @Test("自作語の誤答肢は同じグループの語から選び、ほかのグループ・どのグループにも無い自作語は選ばない")
    func customDistractorsComeFromSameGroup() throws {
        let custom = customEntry("custom-1", word: "homeroom")
        let sameGroupCustom = customEntry("custom-2", word: "lunchbox")
        let otherGroupCustom = customEntry("custom-3", word: "locker")
        let orphanCustom = customEntry("custom-4", word: "commute")  // グループから外した語
        let store = store.including(customWords: [custom, sameGroupCustom, otherGroupCustom, orphanCustom])
        // グループ外の語（a1-0006 actor・custom-3）は選ばれない
        let groups = [["a1-0001", "custom-1", "custom-2", "a1-0004"], ["a1-0006", "custom-3"]]
        for seed in 1...20 {
            var builder = QuizBuilder(store: store, groups: groups, rng: SeededRNG(seed: UInt64(seed)))
            let ids = Set(builder.distractors(for: custom).map(\.id))
            #expect(ids == ["a1-0001", "a1-0004", "custom-2"])
        }
    }

    @Test("グループの語が足りなければ、残りを同梱語の同品詞から埋める（自作語は入れない）")
    func customDistractorsFillFromBundledWords() throws {
        let custom = customEntry("custom-1", word: "homeroom")
        let others = (2...30).map { customEntry("custom-\($0)", word: "custom\($0)") }
        let store = store.including(customWords: [custom] + others)
        for seed in 1...20 {
            var builder = QuizBuilder(
                store: store, groups: [["custom-1", "a2-0001"]], rng: SeededRNG(seed: UInt64(seed))
            )
            let picked = builder.distractors(for: custom)
            #expect(picked.count == QuizBuilder.choiceCount - 1)
            #expect(picked.contains { $0.id == "a2-0001" })
            let filled = picked.filter { $0.id != "a2-0001" }
            #expect(filled.allSatisfy { !$0.isCustom && $0.pos == custom.pos })
        }
    }

    @Test("同梱語の誤答肢に自作語は入らない")
    func bundledDistractorsExcludeCustomWords() throws {
        let customs = (1...30).map { customEntry("custom-\($0)", word: "custom\($0)") }
        let store = store.including(customWords: customs)
        var builder = QuizBuilder(store: store, groups: [["a1-0001", "custom-1"]], rng: SeededRNG(seed: 3))
        for id in ["a1-0001", "a1-0500", "a2-0100", "ph-0001"] {
            let target = try #require(store.word(id: id))
            #expect(builder.distractors(for: target).allSatisfy { !$0.isCustom })
        }
    }

    private func customEntry(_ id: String, word: String) -> WordEntry {
        WordEntry(
            id: id, word: word, pos: .noun, level: nil, meaning: "\(word) の意味",
            example: "", exampleJa: ""
        )
    }

    @Test("穴埋めは例文中の該当語を空欄にする")
    func fillBlankMasksHeadword() throws {
        var builder = builder()
        let target = try word("a1-0004")  // He is a man of action.
        let quiz = builder.make(for: target, type: .fillBlank)
        #expect(quiz.type == .fillBlank)
        let blanked = try #require(quiz.blankedExample)
        #expect(blanked.contains(Quiz.blankPlaceholder))
        #expect(!blanked.localizedCaseInsensitiveContains(target.word))
        #expect(quiz.promptText == blanked)
    }

    @Test("活用している例文でも空欄にできる")
    func fillBlankHandlesInflections() throws {
        var builder = builder()
        // spend → spent（不規則）/ get up → got up（句動詞の活用）
        for id in ["a1-0821", "ph-0005"] {
            let quiz = builder.make(for: try word(id), type: .fillBlank)
            #expect(quiz.type == .fillBlank, "\(id) が英→日にフォールバックした")
            #expect(quiz.blankedExample?.contains(Quiz.blankPlaceholder) == true)
        }
    }

    @Test("空欄化できない語は英→日にフォールバックする")
    func fillBlankFallsBackToEnToJa() {
        let target = WordEntry(
            id: "x-0001", word: "unfindable", pos: .noun, level: .a1,
            meaning: "見つからない語", example: "This sentence has no headword.",
            exampleJa: "この文には見出し語がありません。"
        )
        let others = (1...5).map { index in
            WordEntry(
                id: "x-\(index + 1)", word: "w\(index)", pos: .noun, level: .a1,
                meaning: "意味\(index)", example: "W\(index).", exampleJa: "意味\(index)。"
            )
        }
        let small = WordStore(decks: [Deck(id: "x", name: "x", words: [target] + others)])
        var builder = QuizBuilder(store: small, rng: SeededRNG(seed: 5))
        let quiz = builder.make(for: target, type: .fillBlank)
        #expect(quiz.type == .enToJa)
        #expect(quiz.blankedExample == nil)
    }

    @Test("形式ごとに問題文と選択肢の見せ方が変わる")
    func promptAndChoiceTextPerType() throws {
        var builder = builder()
        let target = try word("a1-0002")

        let enToJa = builder.make(for: target, type: .enToJa)
        #expect(enToJa.promptText == target.word)
        #expect(enToJa.choiceText(target) == target.meaning)

        let jaToEn = builder.make(for: target, type: .jaToEn)
        #expect(jaToEn.promptText == target.meaning)
        #expect(jaToEn.choiceText(target) == target.word)

        let listening = builder.make(for: target, type: .listening)
        #expect(listening.promptText == nil)
        #expect(listening.choiceText(target) == target.meaning)
        #expect(listening.speechOnPrompt?.example == target.example)

        // 日→英 は答えが読み上げで漏れないよう音声を出さない
        #expect(jaToEn.speechOnPrompt == nil)
    }

    // MARK: - 意味が複数ある語

    /// commute（動詞: 通勤する／名詞: 通勤）。例文で空欄にできるのは `blankable` の意味だけにできる
    private func commute(blankable: [PartOfSpeech] = [.verb, .noun]) -> WordEntry {
        WordEntry(
            id: "custom-commute", word: "commute", pos: .verb, level: nil, meaning: "通勤する",
            example: blankable.contains(.verb) ? "I commute by bus." : "I go by bus.", exampleJa: "",
            extraSenses: [
                WordSense(
                    pos: .noun, meaning: "通勤",
                    example: blankable.contains(.noun) ? "My commute is long." : "The trip is long."
                ),
            ]
        )
    }

    @Test("意味が複数ある語は 1 問ごとに意味を選び、問題文・正解の選択肢はその意味で出す")
    func multiSensePicksOneSense() throws {
        let target = commute()
        let store = store.including(customWords: [target])
        var asked: Set<PartOfSpeech> = []
        for seed in 1...20 {
            var builder = QuizBuilder(store: store, rng: SeededRNG(seed: UInt64(seed)))
            let enToJa = builder.make(for: target, type: .enToJa)
            asked.insert(enToJa.sense.pos)
            #expect(enToJa.choiceText(target) == enToJa.sense.meaning)

            let jaToEn = builder.make(for: target, type: .jaToEn)
            #expect(jaToEn.promptText == jaToEn.sense.meaning)
            #expect(target.senses.contains(jaToEn.sense))
        }
        #expect(asked == [.verb, .noun])
    }

    @Test("誤答肢は出題する意味の品詞から選び、正解の語のほかの意味は誤答肢に出さない")
    func multiSenseDistractorsMatchSensePos() throws {
        let target = commute()
        let store = store.including(customWords: [target])
        for seed in 1...20 {
            var builder = QuizBuilder(store: store, rng: SeededRNG(seed: UInt64(seed)))
            let quiz = builder.make(for: target, type: .enToJa)
            let distractors = quiz.choices.filter { $0 != target }
            #expect(distractors.count == QuizBuilder.choiceCount - 1)
            #expect(distractors.allSatisfy { $0.senses.contains { $0.pos == quiz.sense.pos } })
            let texts = distractors.map { quiz.choiceText($0) }
            #expect(!texts.contains("通勤する") && !texts.contains("通勤"))
            #expect(Set(quiz.choices.map { quiz.choiceText($0) }).count == QuizBuilder.choiceCount)
        }
    }

    @Test("正解の語のほかの意味と同じ意味の語は、誤答肢に入らない")
    func otherSenseMeaningIsNotADistractor() {
        let target = commute()
        let others = (1...5).map { index in
            WordEntry(
                id: "x-\(index)", word: "w\(index)", pos: .verb, level: .a1,
                meaning: "意味\(index)", example: "", exampleJa: ""
            )
        }
        // 名詞の「通勤」と同じ意味の語
        let trip = WordEntry(
            id: "x-trip", word: "trip", pos: .verb, level: .a1, meaning: "通勤", example: "", exampleJa: ""
        )
        let deck = Deck(id: "x", name: "x", words: others + [trip])
        let small = WordStore(decks: [deck], customWords: [target])
        for seed in 1...20 {
            var builder = QuizBuilder(store: small, rng: SeededRNG(seed: UInt64(seed)))
            let picked = builder.distractors(for: target, sense: target.primarySense)
            #expect(!picked.contains(trip))
        }
    }

    @Test("誤答肢の語に意味が複数あれば、出題する意味と同じ品詞の意味を見せる")
    func distractorShowsSensesOfSamePos() {
        let target = WordEntry(
            id: "a1-x", word: "walk", pos: .noun, level: .a1, meaning: "散歩", example: "", exampleJa: ""
        )
        let quiz = Quiz(word: target, type: .enToJa, choices: [target, commute()], blankedExample: nil)
        #expect(quiz.choiceText(commute()) == "通勤")
        let verbQuiz = Quiz(
            word: target, sense: WordSense(pos: .verb, meaning: "歩く"), type: .enToJa,
            choices: [target, commute()], blankedExample: nil
        )
        #expect(verbQuiz.choiceText(commute()) == "通勤する")
        #expect(verbQuiz.choiceText(target) == "歩く")
    }

    @Test("穴埋めは、空欄にできる例文のある意味を使う。どの意味でもできなければ英→日")
    func multiSenseFillBlankUsesBlankableSense() throws {
        let nounOnly = commute(blankable: [.noun])
        let store = store.including(customWords: [nounOnly])
        for seed in 1...10 {
            var builder = QuizBuilder(store: store, rng: SeededRNG(seed: UInt64(seed)))
            let quiz = builder.make(for: nounOnly, type: .fillBlank)
            #expect(quiz.type == .fillBlank)
            #expect(quiz.sense.pos == .noun)
            #expect(quiz.blankedExample == "My \(Quiz.blankPlaceholder) is long.")
        }

        let none = commute(blankable: [])
        var builder = QuizBuilder(store: store.including(customWords: [none]), rng: SeededRNG(seed: 3))
        let quiz = builder.make(for: none, type: .fillBlank)
        #expect(quiz.type == .enToJa)
        #expect(quiz.blankedExample == nil)
    }

    @Test("穴埋めで出せるかは、どれかの意味の例文に見出し語があるかで決まる")
    func canFillBlank() throws {
        #expect(QuizBuilder.canFillBlank(try word("a1-0004")))
        #expect(QuizBuilder.canFillBlank(try word("a1-0821")))  // spend → spent
        #expect(QuizBuilder.canFillBlank(commute(blankable: [.noun])))  // 2 つ目の意味だけ空欄にできる
        #expect(!QuizBuilder.canFillBlank(commute(blankable: [])))
        let noExample = WordEntry(
            id: "custom-x", word: "homeroom", pos: .noun, level: nil, meaning: "ホームルーム",
            example: "", exampleJa: ""
        )
        #expect(!QuizBuilder.canFillBlank(noExample))
    }

    @Test("ステージ指定なら形式は SRS の対応表に従う")
    func makeByStageUsesSrsMapping() throws {
        var builder = builder()
        let target = try word("a1-0004")
        #expect(builder.make(for: target, stage: 1).type == .enToJa)
        #expect(builder.make(for: target, stage: 4).type == .jaToEn)
        #expect(builder.make(for: target, stage: 5).type == .listening)
    }
}

@Suite("活用形の照合")
struct InflectorTests {
    @Test("規則変化を照合できる")
    func regularForms() {
        #expect(Inflector.findHeadword(in: "She plays tennis.", headword: "play") != nil)
        #expect(Inflector.findHeadword(in: "He studied hard.", headword: "study") != nil)
        #expect(Inflector.findHeadword(in: "We are stopping here.", headword: "stop") != nil)
        #expect(Inflector.findHeadword(in: "I am making a cake.", headword: "make") != nil)
    }

    @Test("不規則変化を照合できる")
    func irregularForms() {
        #expect(Inflector.findHeadword(in: "I got a letter.", headword: "get") != nil)
        #expect(Inflector.findHeadword(in: "Brush your teeth.", headword: "tooth") != nil)
        #expect(Inflector.findHeadword(in: "She went home.", headword: "go") != nil)
    }

    @Test("熟語は先頭の動詞・末尾の名詞の活用を見る")
    func phraseForms() {
        #expect(Inflector.findHeadword(in: "I woke up late.", headword: "wake up") != nil)
        #expect(Inflector.findHeadword(in: "We played board games.", headword: "board game") != nil)
        #expect(Inflector.findHeadword(in: "She is good at math.", headword: "be good at") != nil)
    }

    @Test("含まれない語は nil を返す")
    func missingHeadword() {
        #expect(Inflector.findHeadword(in: "This is a pen.", headword: "banana") == nil)
        // 部分一致で誤検出しない
        #expect(Inflector.findHeadword(in: "I like pineapple.", headword: "apple") == nil)
    }

    @Test("同梱データの 99% 以上で例文中の見出し語を特定できる")
    func coverageOnBundledData() {
        let words = WordStore.shared.allWords
        let missing = words.filter {
            Inflector.findHeadword(in: $0.example, headword: $0.word) == nil
        }
        let rate = 1 - Double(missing.count) / Double(words.count)
        #expect(rate >= 0.99, "照合できたのは \(rate * 100)%（\(missing.count) 件が未照合）")
    }
}
