import Foundation

/// 1 問分の出題内容。
struct Quiz: Identifiable {
    let id = UUID()
    let word: WordEntry
    let type: QuizType
    /// 正解を含む 4 択（並びはシャッフル済み）
    let choices: [WordEntry]
    /// 穴埋めの問題文（`type == .fillBlank` のときだけ入る）
    let blankedExample: String?

    static let blankPlaceholder = "＿＿＿＿"

    var answerIndex: Int { choices.firstIndex(of: word) ?? 0 }

    /// 画面に出す問題文。リスニングは音声だけなのでテキストは出さない
    var promptText: String? {
        switch type {
        case .enToJa: word.word
        case .fillBlank: blankedExample
        case .jaToEn: word.meaning
        case .listening: nil
        }
    }

    /// 選択肢の表示文字列
    func choiceText(_ entry: WordEntry) -> String {
        switch type {
        case .enToJa, .listening: entry.meaning
        case .fillBlank, .jaToEn: entry.word
        }
    }

    /// 出題時に読み上げる内容。正解が分かってしまう形式では読まない
    var speechOnPrompt: (word: String, example: String)? {
        switch type {
        case .enToJa: (word.word, "")
        case .listening: (word.word, word.example)
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
    mutating func make(for word: WordEntry, type requestedType: QuizType) -> Quiz {
        var type = requestedType
        var blanked: String?

        if type == .fillBlank {
            if let text = blankedExample(for: word) {
                blanked = text
            } else {
                // 例文中に見出し語を見つけられなかったときは英→日にフォールバック
                type = .enToJa
            }
        }

        let choices = (distractors(for: word) + [word]).shuffled(using: &rng)
        return Quiz(word: word, type: type, choices: choices, blankedExample: blanked)
    }

    /// 例文中の該当語を空欄にする。見つからなければ nil
    func blankedExample(for word: WordEntry) -> String? {
        guard let range = Inflector.findHeadword(in: word.example, headword: word.word) else {
            return nil
        }
        return word.example.replacingCharacters(in: range, with: Quiz.blankPlaceholder)
    }

    /// 誤答肢を 3 つ選ぶ。優先するプールから取れるだけ取り、足りない分を次のプールで埋める。
    ///
    /// - 同梱語: 同レベル・同品詞 → 同レベル → 全体
    /// - 自作語: 同じグループの語とほかの自作語（同品詞 → 全品詞）→ 全体の同品詞 → 全体
    ///   （同梱語は A1〜A2 のやさしい語なので、そこからだけ選ぶと消去法で当たってしまう）
    ///
    /// 正解と綴り・意味が同じ語は入れない（同じ綴りが 2 つ並ぶと片方が不正解になってしまう）。
    /// 誤答肢どうしも綴り・意味が重ならないようにする
    mutating func distractors(for word: WordEntry) -> [WordEntry] {
        let needed = Self.choiceCount - 1
        let pools: [[WordEntry]]
        if word.isCustom {
            let related = relatedWords(for: word)
            pools = [
                related.filter { $0.pos == word.pos },
                related,
                store.allWords.filter { $0.pos == word.pos },
                store.allWords,
            ]
        } else {
            let sameLevel = word.level.map { store.words(level: $0) } ?? store.allWords
            pools = [
                sameLevel.filter { $0.pos == word.pos },
                sameLevel,
                store.allWords,
            ]
        }

        var picked: [WordEntry] = []
        var spellings: Set<String> = [WordStore.normalizedSpelling(word.word)]
        var meanings: Set<String> = [word.meaning]
        for pool in pools {
            for candidate in pool.shuffled(using: &rng) {
                guard picked.count < needed else { return picked }
                let spelling = WordStore.normalizedSpelling(candidate.word)
                guard !spellings.contains(spelling), !meanings.contains(candidate.meaning) else {
                    continue
                }
                picked.append(candidate)
                spellings.insert(spelling)
                meanings.insert(candidate.meaning)
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
