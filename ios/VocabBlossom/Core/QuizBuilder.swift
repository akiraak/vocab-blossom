import Foundation

/// 穴埋めの答え方
enum QuizInput: Equatable, Sendable {
    /// 4 択から選ぶ
    case choice
    /// 空欄に入る語をキーボードで打つ（グループの穴埋めモードだけ）
    case typing
}

/// 1 問分の出題内容。
///
/// 意味が複数ある語（自作語）は、1 問ごとに意味を 1 つ選んで出す（`sense`）。
/// 誤答肢の語は、出題する意味と同じ品詞の意味を見せる（無ければ 1 つ目の意味）
struct Quiz: Identifiable {
    let id = UUID()
    let word: WordEntry
    /// 出題する意味（意味が 1 つの語は 1 つ目の意味）
    let sense: WordSense
    let type: QuizType
    /// 答え方。入力（`.typing`）は穴埋めだけで、選択肢を持たない
    let input: QuizInput
    /// 正解を含む 4 択（並びはシャッフル済み）。入力の問題は空
    let choices: [WordEntry]
    /// 穴埋めの問題文（`type == .fillBlank` のときだけ入る）
    let blankedExample: String?
    /// 穴埋めに使った文章（例文で出したときは nil）。答えたあと全文と和訳を見せる
    let passage: Passage?
    /// 使った文章が、その意味の文章の何番目か（0 始まり）。回答したら `PassageHistory` に残し、次は別の文章を出す
    let passageIndex: Int?
    /// 誤答肢のうち、空欄に入れても正しい文になる語（AI の判定。グループの穴埋めモードだけ）。選ぶと正解にする
    let alsoCorrectWordIds: Set<String>
    /// 入力の問題の正解の綴り: 文中で空欄にした形（見出し語 adapt でも文中が adapted なら adapted）。
    /// 空欄が 2 か所の語（either … or …）は空白でつなぐ（either or）
    let typedAnswer: String?

    static let blankPlaceholder = "＿＿＿＿"

    init(
        word: WordEntry,
        sense: WordSense? = nil,
        type: QuizType,
        choices: [WordEntry],
        blankedExample: String?,
        passage: Passage? = nil,
        passageIndex: Int? = nil,
        alsoCorrectWordIds: Set<String> = [],
        input: QuizInput = .choice,
        typedAnswer: String? = nil
    ) {
        self.input = input
        self.typedAnswer = input == .typing ? typedAnswer : nil
        self.word = word
        self.sense = sense ?? word.primarySense
        self.type = type
        self.choices = choices
        self.blankedExample = blankedExample
        self.passage = passage
        self.passageIndex = passage == nil ? nil : passageIndex
        self.alsoCorrectWordIds = alsoCorrectWordIds.subtracting([word.id])
    }

    /// 出題した語の位置
    var answerIndex: Int { choices.firstIndex(of: word) ?? 0 }

    /// 選んだ選択肢が正解か（出題した語か、ほかにも正解の語）
    func isCorrect(choiceIndex: Int) -> Bool {
        guard choices.indices.contains(choiceIndex) else { return false }
        return choiceIndex == answerIndex || alsoCorrectWordIds.contains(choices[choiceIndex].id)
    }

    /// 打った綴りが正解か。前後・連続の空白、大文字小文字、アポストロフィの形の違いは見ない。
    /// 綴りや活用が違えば不正解（文中が adapted なら adapt は不正解）
    func isCorrect(typed: String) -> Bool {
        guard let typedAnswer else { return false }
        let normalized = Self.normalizedTyped(typed)
        return !normalized.isEmpty && normalized == Self.normalizedTyped(typedAnswer)
    }

    /// 打った綴りが、見出し語そのもので、文中の形とは違うか（「この文では adapted の形」と添える）
    func isHeadwordInOtherForm(typed: String) -> Bool {
        !isCorrect(typed: typed) && Self.normalizedTyped(typed) == Self.normalizedTyped(word.word)
    }

    /// 比べる前にそろえる: 空白をまとめる・小文字にする・「’」を「'」にする
    static func normalizedTyped(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// ほかにも正解の語（選択肢の並び順）
    var alsoCorrectChoices: [WordEntry] {
        choices.filter { alsoCorrectWordIds.contains($0.id) }
    }

    /// 穴埋めで空欄にした元の文（文章か例文）。穴埋めでなければ nil
    var fillBlankSourceText: String? {
        guard type == .fillBlank, blankedExample != nil else { return nil }
        return passage?.text ?? sense.example
    }

    /// ほかにも正解の語を入れた問題（中身は同じで、別の問題として出す）
    func with(alsoCorrectWordIds ids: Set<String>) -> Quiz {
        Quiz(
            word: word, sense: sense, type: type, choices: choices, blankedExample: blankedExample,
            passage: passage, passageIndex: passageIndex, alsoCorrectWordIds: ids,
            input: input, typedAnswer: typedAnswer
        )
    }

    /// 選択肢の並びだけ変えた問題（再出題用）
    func reshuffled(using rng: inout some RandomNumberGenerator) -> Quiz {
        Quiz(
            word: word, sense: sense, type: type, choices: choices.shuffled(using: &rng),
            blankedExample: blankedExample, passage: passage, passageIndex: passageIndex,
            alsoCorrectWordIds: alsoCorrectWordIds, input: input, typedAnswer: typedAnswer
        )
    }

    /// 選択肢の語に見せる意味。正解は出題する意味、誤答肢は同じ品詞の意味
    func sense(of entry: WordEntry) -> WordSense {
        entry == word ? sense : entry.sense(for: sense.pos)
    }

    /// 画面に出す問題文。リスニングは音声だけなのでテキストは出さない
    var promptText: String? {
        switch type {
        case .enToJa: word.word
        case .fillBlank: blankedExample
        case .jaToEn: sense.meaning
        case .listening: nil
        }
    }

    /// 選択肢の表示文字列
    func choiceText(_ entry: WordEntry) -> String {
        switch type {
        case .enToJa, .listening: sense(of: entry).meaning
        case .fillBlank, .jaToEn: entry.word
        }
    }

    /// 出題時に読み上げる内容。正解が分かってしまう形式では読まない
    var speechOnPrompt: (word: String, example: String)? {
        switch type {
        case .enToJa: (word.word, "")
        case .listening: (word.word, sense.example)
        case .fillBlank, .jaToEn: nil
        }
    }
}

/// 誤答肢を選ぶのに使うグループ（名前と単語 ID の並び）
struct QuizGroup: Equatable, Sendable {
    var name: String
    var wordIds: [String]

    /// つなぎ言葉のグループの名前の頭。データは data/groups/connectives.json
    static let connectivePrefix = "つなぎ言葉・"

    /// つなぎ言葉のグループなら働きの名前（「つなぎ言葉・逆接と対比 2」→「逆接と対比」）。そうでなければ nil。
    ///
    /// 似た語を「1」「2」に分けたグループは同じ働きとみなす（末尾の番号を除く）
    var connectiveFunction: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(Self.connectivePrefix) else { return nil }
        let function = trimmed.dropFirst(Self.connectivePrefix.count)
            .replacingOccurrences(of: "\\s*[0-9０-９]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return function.isEmpty ? nil : function
    }
}

/// 穴埋めに選んだ文章（その意味の文章の何番目か・空欄にした文と元の綴り・元の文章）
private struct PickedPassage {
    let index: Int
    let blanked: BlankedText
    let passage: Passage
}

/// 見出し語を空欄にした文と、空欄にした元の綴り（2 か所なら空白でつなぐ）
struct BlankedText: Equatable {
    let text: String
    let surface: String
}

/// ステージに応じた出題を組み立てる。
struct QuizBuilder {
    /// 4 択の選択肢数
    static let choiceCount = 4

    let store: WordStore
    /// グループ。自作語の誤答肢を同じグループの語から、つなぎ言葉の誤答肢を働きの違うグループの語から選ぶのに使う
    let groups: [QuizGroup]
    /// 穴埋め用の文章（端末にためたもの）。あれば例文より優先して使う
    let passages: PassageLookup
    /// 最後に出した文章。あれば前回の次の文章から出す（nil なら毎回 1 つ目から）
    let passageHistory: PassageHistory?
    var rng: any RandomNumberGenerator

    init(
        store: WordStore,
        groups: [QuizGroup] = [],
        passages: @escaping PassageLookup = Passages.none,
        passageHistory: PassageHistory? = nil,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.store = store
        self.groups = groups
        self.passages = passages
        self.passageHistory = passageHistory
        self.rng = rng
    }

    /// ステージから形式を決めて 1 問作る。
    mutating func make(for word: WordEntry, stage: Int) -> Quiz {
        make(for: word, type: SRS.quizType(for: stage))
    }

    /// 形式を指定して 1 問作る（新規学習の直後クイズは常に英→日）。
    ///
    /// 意味が複数ある語は、出題する意味を 1 つ選ぶ。穴埋めは空欄にできる文章のある意味を選び、その意味の文章を
    /// 前回出した文章の次から順に出す（`nextPassage`）。文章が無ければ例文を使い、どの意味でも空欄にできなければ
    /// 英→日にフォールバックする
    ///
    /// `input` が `.typing` なら、選択肢を作らず、空欄にした綴りを正解に持つ問題にする（穴埋めにできたときだけ）
    mutating func make(
        for word: WordEntry, type requestedType: QuizType, input: QuizInput = .choice
    ) -> Quiz {
        var type = requestedType
        var blanked: BlankedText?
        var passage: Passage?
        var passageIndex: Int?
        var sense = pickSense(from: word.senses)

        if type == .fillBlank {
            let fromPassages = word.senses.compactMap { sense in
                nextPassage(for: word, sense: sense).map { (sense: sense, picked: $0) }
            }
            let fromExamples = word.senses.compactMap { sense in
                Self.blankedText(sense.example, headword: word.word).map { (sense: sense, text: $0) }
            }
            if let chosen = pickSense(from: fromPassages) {
                sense = chosen.sense
                blanked = chosen.picked.blanked
                passage = chosen.picked.passage
                passageIndex = chosen.picked.index
            } else if let picked = pickSense(from: fromExamples) {
                sense = picked.sense
                blanked = picked.text
            } else {
                // 例文中に見出し語を見つけられなかったときは英→日にフォールバック
                type = .enToJa
            }
        }

        if input == .typing, type == .fillBlank, let blanked {
            return Quiz(
                word: word, sense: sense, type: type, choices: [], blankedExample: blanked.text,
                passage: passage, passageIndex: passageIndex, input: .typing, typedAnswer: blanked.surface
            )
        }
        let choices = (distractors(for: word, sense: sense) + [word]).shuffled(using: &rng)
        return Quiz(
            word: word, sense: sense, type: type, choices: choices, blankedExample: blanked?.text,
            passage: passage, passageIndex: passageIndex
        )
    }

    /// その意味の文章のうち、前回出した文章の次から順に見て、最初に空欄にできるもの（最後の次は最初に戻る）。
    /// 出したことが無ければ 1 つ目から見る。空欄にできる文章が無ければ nil
    private func nextPassage(for word: WordEntry, sense: WordSense) -> PickedPassage? {
        let candidates = passages(word, sense)
        guard !candidates.isEmpty else { return nil }
        let start = max(0, passageHistory?.lastShownIndex(word: word.word, sense: sense).map { $0 + 1 } ?? 0)
        for offset in candidates.indices {
            let index = (start + offset) % candidates.count
            if let blanked = Self.blankedText(candidates[index].text, headword: word.word) {
                return PickedPassage(index: index, blanked: blanked, passage: candidates[index])
            }
        }
        return nil
    }

    /// 選択肢の並びだけ変えた問題（組み立て済みの問題の再出題用）
    mutating func reshuffle(_ quiz: Quiz) -> Quiz {
        quiz.reshuffled(using: &rng)
    }

    /// 1 つなら乱数を使わずにそれを返す（意味が 1 つの語で、これまでと同じ乱数の並びにする）
    private mutating func pickSense<T>(from items: [T]) -> T? {
        items.count > 1 ? items.randomElement(using: &rng) : items.first
    }

    /// どれかの意味の文章か例文で見出し語を空欄にできるか（穴埋めで出せるか）
    static func canFillBlank(_ word: WordEntry, passages: PassageLookup = Passages.none) -> Bool {
        word.senses.contains { sense in
            blank(sense.example, headword: word.word) != nil
                || passages(word, sense).contains { blank($0.text, headword: word.word) != nil }
        }
    }

    /// 文中の見出し語（活用形を含む）を空欄にする。見つからなければ nil。
    /// 「either … or …」は区切りごとに空欄にする（「＿＿＿＿ tea ＿＿＿＿ coffee is fine.」のように 2 か所になる）
    static func blank(_ text: String, headword: String) -> String? {
        blankedText(text, headword: headword)?.text
    }

    /// 空欄にした文と、空欄にした元の綴り（入力の問題の正解になる）。見つからなければ nil
    static func blankedText(_ text: String, headword: String) -> BlankedText? {
        guard let ranges = Inflector.findHeadwordRanges(in: text, headword: headword) else { return nil }
        let surface = ranges.map { String(text[$0]) }.joined(separator: " ")
        var blanked = text
        // 後ろから置き換えて、前の範囲がずれないようにする
        for range in ranges.reversed() {
            blanked.replaceSubrange(range, with: Quiz.blankPlaceholder)
        }
        return BlankedText(text: blanked, surface: surface)
    }

    /// 例文中の該当語を空欄にする。見つからなければ nil
    func blankedExample(for word: WordEntry) -> String? {
        blankedExample(for: word, sense: word.primarySense)
    }

    /// 意味の例文中の該当語を空欄にする。見つからなければ nil
    func blankedExample(for word: WordEntry, sense: WordSense) -> String? {
        Self.blank(sense.example, headword: word.word)
    }

    /// 誤答肢を 3 つ選ぶ。優先するプールから取れるだけ取り、足りない分を次のプールで埋める。
    ///
    /// - 同梱語: 同レベル・同品詞 → 同レベル → 同梱語の全体
    /// - 自作語: 同じグループの語（同品詞 → 全品詞）→ 同梱語の同品詞 → 同梱語の全体
    ///   （同梱語は A1〜A2 のやさしい語なので、そこからだけ選ぶと消去法で当たってしまう）
    ///
    /// 自作語を誤答肢にするのは、出題する語と同じグループに入っているものだけ。
    /// グループから外した自作語や、ほかのグループの自作語が選択肢に出ると不自然なため
    ///
    /// つなぎ言葉のグループ（`QuizGroup.connectiveFunction`）に入っている語は、その前に
    /// 働きの違うつなぎ言葉のグループの語（同品詞 → 全品詞）を使う。同じ働きの語（because と since など）が並ぶと、
    /// どれを入れても文が成り立ってしまうため。同じ働きの 1・2 のグループの語も使わない
    ///
    /// 品詞は出題する意味（`sense`。省略時は 1 つ目の意味）に合わせる。
    /// 意味が複数ある語は、どれかの意味が同じ品詞なら同品詞とみなす。
    ///
    /// 正解と綴り・意味が同じ語は入れない（同じ綴りが 2 つ並ぶと片方が不正解になってしまう）。
    /// 正解の語のほかの意味と同じ意味も入れない。誤答肢どうしも綴り・意味が重ならないようにする
    mutating func distractors(for word: WordEntry, sense: WordSense? = nil) -> [WordEntry] {
        let needed = Self.choiceCount - 1
        let pos = (sense ?? word.primarySense).pos
        func samePos(_ entry: WordEntry) -> Bool { entry.senses.contains { $0.pos == pos } }
        var pools: [[WordEntry]]
        if word.isCustom {
            let related = relatedWords(for: word)
            pools = [
                related.filter(samePos),
                related,
                store.bundledWords.filter(samePos),
                store.bundledWords,
            ]
        } else {
            let sameLevel = word.level.map { store.words(level: $0) } ?? store.bundledWords
            pools = [
                sameLevel.filter(samePos),
                sameLevel,
                store.bundledWords,
            ]
        }
        let otherConnectives = otherFunctionConnectives(for: word)
        if !otherConnectives.isEmpty {
            pools.insert(contentsOf: [otherConnectives.filter(samePos), otherConnectives], at: 0)
        }

        var picked: [WordEntry] = []
        var spellings: Set<String> = [WordStore.normalizedSpelling(word.word)]
        var meanings = Set(word.senses.map(\.meaning))
        for pool in pools {
            for candidate in pool.shuffled(using: &rng) {
                guard picked.count < needed else { return picked }
                let spelling = WordStore.normalizedSpelling(candidate.word)
                // 画面に出すのは、出題する意味と同じ品詞の意味
                let meaning = candidate.sense(for: pos).meaning
                guard !spellings.contains(spelling), !meanings.contains(meaning) else {
                    continue
                }
                picked.append(candidate)
                spellings.insert(spelling)
                meanings.insert(meaning)
            }
            if picked.count >= needed { return picked }
        }
        return picked
    }

    /// 自作語と関係の近い語: その語が入っているグループの語（重複なし・本人を除く）
    func relatedWords(for word: WordEntry) -> [WordEntry] {
        let groupIds = groups.filter { $0.wordIds.contains(word.id) }.flatMap(\.wordIds)
        var seen: Set<String> = [word.id]
        return store.words(ids: groupIds).filter { seen.insert($0.id).inserted }
    }

    /// つなぎ言葉の語の誤答肢の候補: 働きの違うつなぎ言葉のグループの語（重複なし）。
    /// 出題する語が入っている働きのグループの語は除く。つなぎ言葉のグループに入っていない語は空
    func otherFunctionConnectives(for word: WordEntry) -> [WordEntry] {
        let ownGroups = groups.filter { $0.wordIds.contains(word.id) }
        let ownFunctions = Set(ownGroups.compactMap(\.connectiveFunction))
        guard !ownFunctions.isEmpty else { return [] }
        var excluded = Set(
            groups.filter { $0.connectiveFunction.map(ownFunctions.contains) ?? false }.flatMap(\.wordIds)
        )
        excluded.insert(word.id)
        let ids = groups
            .filter { $0.connectiveFunction.map { !ownFunctions.contains($0) } ?? false }
            .flatMap(\.wordIds)
            .filter { excluded.insert($0).inserted }
        return store.words(ids: ids)
    }
}
