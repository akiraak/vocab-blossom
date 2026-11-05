import Foundation

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
    /// 正解を含む 4 択（並びはシャッフル済み）
    let choices: [WordEntry]
    /// 穴埋めの問題文（`type == .fillBlank` のときだけ入る）
    let blankedExample: String?
    /// 穴埋めに使った文章（例文で出したときは nil）。答えたあと全文と和訳を見せる
    let passage: Passage?
    /// 誤答肢のうち、空欄に入れても正しい文になる語（AI の判定。グループの穴埋めモードだけ）。選ぶと正解にする
    let alsoCorrectWordIds: Set<String>

    static let blankPlaceholder = "＿＿＿＿"

    init(
        word: WordEntry,
        sense: WordSense? = nil,
        type: QuizType,
        choices: [WordEntry],
        blankedExample: String?,
        passage: Passage? = nil,
        alsoCorrectWordIds: Set<String> = []
    ) {
        self.word = word
        self.sense = sense ?? word.primarySense
        self.type = type
        self.choices = choices
        self.blankedExample = blankedExample
        self.passage = passage
        self.alsoCorrectWordIds = alsoCorrectWordIds.subtracting([word.id])
    }

    /// 出題した語の位置
    var answerIndex: Int { choices.firstIndex(of: word) ?? 0 }

    /// 選んだ選択肢が正解か（出題した語か、ほかにも正解の語）
    func isCorrect(choiceIndex: Int) -> Bool {
        guard choices.indices.contains(choiceIndex) else { return false }
        return choiceIndex == answerIndex || alsoCorrectWordIds.contains(choices[choiceIndex].id)
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
            passage: passage, alsoCorrectWordIds: ids
        )
    }

    /// 選択肢の並びだけ変えた問題（再出題用）
    func reshuffled(using rng: inout some RandomNumberGenerator) -> Quiz {
        Quiz(
            word: word, sense: sense, type: type, choices: choices.shuffled(using: &rng),
            blankedExample: blankedExample, passage: passage, alsoCorrectWordIds: alsoCorrectWordIds
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

/// ステージに応じた出題を組み立てる。
struct QuizBuilder {
    /// 4 択の選択肢数
    static let choiceCount = 4

    let store: WordStore
    /// グループ。自作語の誤答肢を同じグループの語から、つなぎ言葉の誤答肢を働きの違うグループの語から選ぶのに使う
    let groups: [QuizGroup]
    /// 穴埋め用の文章（端末にためたもの）。あれば例文より優先して使う
    let passages: PassageLookup
    var rng: any RandomNumberGenerator

    init(
        store: WordStore,
        groups: [QuizGroup] = [],
        passages: @escaping PassageLookup = Passages.none,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.store = store
        self.groups = groups
        self.passages = passages
        self.rng = rng
    }

    /// ステージから形式を決めて 1 問作る。
    mutating func make(for word: WordEntry, stage: Int) -> Quiz {
        make(for: word, type: SRS.quizType(for: stage))
    }

    /// 形式を指定して 1 問作る（新規学習の直後クイズは常に英→日）。
    ///
    /// 意味が複数ある語は、出題する意味を 1 つ選ぶ。穴埋めは空欄にできる文章（無ければ例文）から 1 つ選び、
    /// どの意味でも空欄にできなければ英→日にフォールバックする
    mutating func make(for word: WordEntry, type requestedType: QuizType) -> Quiz {
        var type = requestedType
        var blanked: String?
        var passage: Passage?
        var sense = pickSense(from: word.senses)

        if type == .fillBlank {
            let fromPassages = word.senses.flatMap { sense in
                passages(word, sense).compactMap { candidate in
                    Self.blank(candidate.text, headword: word.word)
                        .map { (sense: sense, text: $0, passage: candidate) }
                }
            }
            let fromExamples = word.senses.compactMap { sense in
                blankedExample(for: word, sense: sense).map { (sense: sense, text: $0) }
            }
            if let picked = pickSense(from: fromPassages) {
                sense = picked.sense
                blanked = picked.text
                passage = picked.passage
            } else if let picked = pickSense(from: fromExamples) {
                sense = picked.sense
                blanked = picked.text
            } else {
                // 例文中に見出し語を見つけられなかったときは英→日にフォールバック
                type = .enToJa
            }
        }

        let choices = (distractors(for: word, sense: sense) + [word]).shuffled(using: &rng)
        return Quiz(
            word: word, sense: sense, type: type, choices: choices, blankedExample: blanked, passage: passage
        )
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
        guard let ranges = Inflector.findHeadwordRanges(in: text, headword: headword) else { return nil }
        var blanked = text
        // 後ろから置き換えて、前の範囲がずれないようにする
        for range in ranges.reversed() {
            blanked.replaceSubrange(range, with: Quiz.blankPlaceholder)
        }
        return blanked
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
