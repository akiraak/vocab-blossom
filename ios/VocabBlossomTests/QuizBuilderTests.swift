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
