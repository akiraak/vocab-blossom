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
        let groups = quizGroups([["a1-0001", "custom-1", "custom-2", "a1-0004"], ["a1-0006", "custom-3"]])
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
                store: store, groups: quizGroups([["custom-1", "a2-0001"]]),
                rng: SeededRNG(seed: UInt64(seed))
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
        var builder = QuizBuilder(
            store: store, groups: quizGroups([["a1-0001", "custom-1"]]), rng: SeededRNG(seed: 3)
        )
        for id in ["a1-0001", "a1-0500", "a2-0100", "ph-0001"] {
            let target = try #require(store.word(id: id))
            #expect(builder.distractors(for: target).allSatisfy { !$0.isCustom })
        }
    }

    // MARK: - つなぎ言葉

    @Test("つなぎ言葉のグループは名前で見分け、末尾の番号を除いた働きの名前を返す")
    func connectiveFunctionFromName() {
        #expect(QuizGroup(name: "つなぎ言葉・逆接と対比 2", wordIds: []).connectiveFunction == "逆接と対比")
        #expect(QuizGroup(name: "つなぎ言葉・逆接と対比 1", wordIds: []).connectiveFunction == "逆接と対比")
        #expect(QuizGroup(name: "つなぎ言葉・条件", wordIds: []).connectiveFunction == "条件")
        #expect(QuizGroup(name: "Unit 3", wordIds: []).connectiveFunction == nil)
        #expect(QuizGroup(name: "つなぎ言葉・", wordIds: []).connectiveFunction == nil)
    }

    /// 時 1・時 2・条件・理由の 4 グループ（語はすべて接続詞のマイ単語）
    private func connectiveFixture() -> (store: WordStore, groups: [QuizGroup]) {
        let ids = (1...12).map { "custom-\($0)" }
        let words = ids.enumerated().map { index, id in
            customEntry(id, word: "conj\(index + 1)", pos: .conjunction)
        }
        let groups = [
            QuizGroup(name: "つなぎ言葉・時 1", wordIds: Array(ids[0..<3])),
            QuizGroup(name: "つなぎ言葉・時 2", wordIds: Array(ids[3..<6])),
            QuizGroup(name: "つなぎ言葉・条件", wordIds: Array(ids[6..<9])),
            QuizGroup(name: "つなぎ言葉・理由と結果 1", wordIds: Array(ids[9..<12])),
        ]
        return (store.including(customWords: words), groups)
    }

    @Test("つなぎ言葉の誤答肢は、働きの違うグループから選ぶ（同じ働きの 1・2 のグループからは選ばない）")
    func connectiveDistractorsComeFromOtherFunctions() throws {
        let (store, groups) = connectiveFixture()
        let target = try #require(store.word(id: "custom-1"))
        let otherFunctions = Set((7...12).map { "custom-\($0)" })
        for seed in 1...20 {
            var builder = QuizBuilder(store: store, groups: groups, rng: SeededRNG(seed: UInt64(seed)))
            let ids = Set(builder.distractors(for: target).map(\.id))
            #expect(ids.count == QuizBuilder.choiceCount - 1)
            #expect(ids.isSubset(of: otherFunctions))
        }
    }

    @Test("つなぎ言葉のグループに入った単語帳の語も、働きの違うグループから誤答肢を選ぶ")
    func bundledConnectiveDistractorsComeFromOtherFunctions() throws {
        let (store, fixtureGroups) = connectiveFixture()
        var groups = fixtureGroups
        groups[0].wordIds.append("a1-0075")  // before（単語帳の語）を時 1 に入れる
        let target = try #require(store.word(id: "a1-0075"))
        let otherFunctions = Set((7...12).map { "custom-\($0)" })
        for seed in 1...20 {
            var builder = QuizBuilder(store: store, groups: groups, rng: SeededRNG(seed: UInt64(seed)))
            #expect(Set(builder.distractors(for: target).map(\.id)).isSubset(of: otherFunctions))
        }
    }

    @Test("働きの違うグループの語が足りなければ、残りは今までのプール（同じグループの語など）で埋める")
    func connectiveDistractorsFallBack() throws {
        let words = (1...4).map { customEntry("custom-\($0)", word: "conj\($0)", pos: .conjunction) }
        let store = store.including(customWords: words)
        let groups = [
            QuizGroup(name: "つなぎ言葉・時 1", wordIds: ["custom-1", "custom-2", "custom-3"]),
            QuizGroup(name: "つなぎ言葉・条件", wordIds: ["custom-4"]),
        ]
        let target = try #require(store.word(id: "custom-1"))
        for seed in 1...20 {
            var builder = QuizBuilder(store: store, groups: groups, rng: SeededRNG(seed: UInt64(seed)))
            let ids = Set(builder.distractors(for: target).map(\.id))
            #expect(ids.count == QuizBuilder.choiceCount - 1)
            #expect(ids.contains("custom-4"))
        }
    }

    @Test("つなぎ言葉でないグループの語は、ほかのグループにつなぎ言葉があっても今のまま同じグループから選ぶ")
    func nonConnectiveGroupUnaffected() throws {
        let (fixtureStore, fixtureGroups) = connectiveFixture()
        let custom = customEntry("custom-x", word: "homeroom")
        // including は自作語を置き換えるので、つなぎ言葉の語と合わせて渡す
        let store = fixtureStore.including(customWords: fixtureStore.customWords + [custom])
        let groups = fixtureGroups + [
            QuizGroup(name: "Unit 3", wordIds: ["custom-x", "a1-0001", "a1-0004", "a1-0006"]),
        ]
        var builder = QuizBuilder(store: store, groups: groups, rng: SeededRNG(seed: 1))
        #expect(Set(builder.distractors(for: custom).map(\.id)) == ["a1-0001", "a1-0004", "a1-0006"])
    }

    private func quizGroups(_ ids: [[String]]) -> [QuizGroup] {
        ids.enumerated().map { QuizGroup(name: "グループ \($0.offset + 1)", wordIds: $0.element) }
    }

    private func customEntry(_ id: String, word: String, pos: PartOfSpeech = .noun) -> WordEntry {
        WordEntry(
            id: id, word: word, pos: pos, level: nil, meaning: "\(word) の意味",
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

@Suite("穴埋めの空欄")
struct BlankTests {
    @Test("「…」を含む見出し語は区切りごとに空欄にする")
    func ellipsisBlanks() {
        #expect(
            QuizBuilder.blank("You can have either cake or ice cream.", headword: "either … or …")
                == "You can have ＿＿＿＿ cake ＿＿＿＿ ice cream."
        )
        #expect(
            QuizBuilder.blank("She is not only smart but also kind.", headword: "not only … but also …")
                == "She is ＿＿＿＿ smart ＿＿＿＿ kind."
        )
    }

    @Test("ふつうの見出し語は 1 か所を空欄にする")
    func singleBlank() {
        #expect(QuizBuilder.blank("She plays tennis.", headword: "play") == "She ＿＿＿＿ tennis.")
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

    @Test("「…」を含む見出し語は、間に語を挟んで区切りごとに見つける")
    func ellipsisRanges() throws {
        let cases: [(text: String, headword: String, parts: [String])] = [
            ("You can have either cake or ice cream.", "either … or …", ["either", "or"]),
            ("He can neither swim nor ride a bike.", "neither … nor …", ["neither", "nor"]),
            ("She is not only smart but also kind.", "not only … but also …", ["not only", "but also"]),
            ("Both my father and my mother are teachers.", "both … and …", ["Both", "and"]),
            ("You can have either cake or ice cream.", "either ... or ...", ["either", "or"]),
        ]
        for item in cases {
            let ranges = try #require(Inflector.findHeadwordRanges(in: item.text, headword: item.headword))
            #expect(ranges.map { String(item.text[$0]) } == item.parts)
        }
        // 全体の範囲は、最初の区切りから最後の区切りまで
        let text = "You can have either cake or ice cream."
        let whole = try #require(Inflector.findHeadword(in: text, headword: "either … or …"))
        #expect(text[whole] == "either cake or")
    }

    @Test("「…」を含む見出し語: 区切りがほかの語の一部・間が無い・間が長すぎる・片方しか無いときは当たらない")
    func ellipsisMisses() {
        #expect(Inflector.findHeadword(in: "Either orange juice is fine.", headword: "either … or …") == nil)
        #expect(Inflector.findHeadword(in: "Either or is fine.", headword: "either … or …") == nil)
        #expect(Inflector.findHeadword(
            in: "Either one two three four five six seven or eight.", headword: "either … or …"
        ) == nil)
        #expect(Inflector.findHeadword(in: "I have both cats.", headword: "both … and …") == nil)
    }

    @Test("ふつうの見出し語の範囲は 1 つ")
    func singleRange() throws {
        let ranges = try #require(Inflector.findHeadwordRanges(in: "She plays tennis.", headword: "play"))
        #expect(ranges.count == 1)
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
