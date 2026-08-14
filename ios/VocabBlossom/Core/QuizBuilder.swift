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
    var rng: any RandomNumberGenerator

    init(store: WordStore, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.store = store
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

    /// 誤答肢は同レベル・同品詞から。足りなければ同レベル → 全体へ広げる
    mutating func distractors(for word: WordEntry) -> [WordEntry] {
        let needed = Self.choiceCount - 1
        let sameLevel = store.words(level: word.level)
        let pools = [
            sameLevel.filter { $0.pos == word.pos },
            sameLevel,
            store.allWords,
        ]
        for pool in pools {
            let candidates = pool.filter { $0.id != word.id && $0.meaning != word.meaning }
            guard candidates.count >= needed else { continue }
            return Array(candidates.shuffled(using: &rng).prefix(needed))
        }
        return []
    }
}
