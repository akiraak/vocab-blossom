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

    static let blankPlaceholder = "＿＿＿＿"

    init(
        word: WordEntry,
        sense: WordSense? = nil,
        type: QuizType,
        choices: [WordEntry],
        blankedExample: String?
    ) {
        self.word = word
        self.sense = sense ?? word.primarySense
        self.type = type
        self.choices = choices
        self.blankedExample = blankedExample
    }

    var answerIndex: Int { choices.firstIndex(of: word) ?? 0 }

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

/// ステージに応じた出題を組み立てる。
struct QuizBuilder {
    /// 4 択の選択肢数
    static let choiceCount = 4

    let store: WordStore
    /// グループごとの単語 ID の並び。自作語の誤答肢を同じグループの語から優先して選ぶのに使う
    let groups: [[String]]
    var rng: any RandomNumberGenerator

    init(
        store: WordStore,
        groups: [[String]] = [],
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.store = store
        self.groups = groups
        self.rng = rng
    }

    /// ステージから形式を決めて 1 問作る。
    mutating func make(for word: WordEntry, stage: Int) -> Quiz {
        make(for: word, type: SRS.quizType(for: stage))
    }

    /// 形式を指定して 1 問作る（新規学習の直後クイズは常に英→日）。
    ///
    /// 意味が複数ある語は、出題する意味を 1 つ選ぶ。穴埋めは空欄にできる例文のある意味から選び、
    /// どの意味でも空欄にできなければ英→日にフォールバックする
    mutating func make(for word: WordEntry, type requestedType: QuizType) -> Quiz {
        var type = requestedType
        var blanked: String?
        var sense = pickSense(from: word.senses)

        if type == .fillBlank {
            let blankable = word.senses.compactMap { sense in
                blankedExample(for: word, sense: sense).map { (sense: sense, text: $0) }
            }
            if let picked = pickSense(from: blankable) {
                sense = picked.sense
                blanked = picked.text
            } else {
                // 例文中に見出し語を見つけられなかったときは英→日にフォールバック
                type = .enToJa
            }
        }

        let choices = (distractors(for: word, sense: sense) + [word]).shuffled(using: &rng)
        return Quiz(word: word, sense: sense, type: type, choices: choices, blankedExample: blanked)
    }

    /// 1 つなら乱数を使わずにそれを返す（意味が 1 つの語で、これまでと同じ乱数の並びにする）
    private mutating func pickSense<T>(from items: [T]) -> T? {
        items.count > 1 ? items.randomElement(using: &rng) : items.first
    }

    /// 例文中の該当語を空欄にする。見つからなければ nil
    func blankedExample(for word: WordEntry) -> String? {
        blankedExample(for: word, sense: word.primarySense)
    }

    /// 意味の例文中の該当語を空欄にする。見つからなければ nil
    func blankedExample(for word: WordEntry, sense: WordSense) -> String? {
        guard let range = Inflector.findHeadword(in: sense.example, headword: word.word) else {
            return nil
        }
        return sense.example.replacingCharacters(in: range, with: Quiz.blankPlaceholder)
    }

    /// 誤答肢を 3 つ選ぶ。優先するプールから取れるだけ取り、足りない分を次のプールで埋める。
    ///
    /// - 同梱語: 同レベル・同品詞 → 同レベル → 全体
    /// - 自作語: 同じグループの語とほかの自作語（同品詞 → 全品詞）→ 全体の同品詞 → 全体
    ///   （同梱語は A1〜A2 のやさしい語なので、そこからだけ選ぶと消去法で当たってしまう）
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
        let pools: [[WordEntry]]
        if word.isCustom {
            let related = relatedWords(for: word)
            pools = [
                related.filter(samePos),
                related,
                store.allWords.filter(samePos),
                store.allWords,
            ]
        } else {
            let sameLevel = word.level.map { store.words(level: $0) } ?? store.allWords
            pools = [
                sameLevel.filter(samePos),
                sameLevel,
                store.allWords,
            ]
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

    /// 自作語と関係の近い語: その語が入っているグループの語 ＋ ほかの自作語（重複なし・本人を除く）
    func relatedWords(for word: WordEntry) -> [WordEntry] {
        let groupIds = groups.filter { $0.contains(word.id) }.flatMap { $0 }
        var seen: Set<String> = [word.id]
        return (store.words(ids: groupIds) + store.customWords).filter { seen.insert($0.id).inserted }
    }
}
