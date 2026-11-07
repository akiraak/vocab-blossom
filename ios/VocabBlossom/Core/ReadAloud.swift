import Foundation

/// 読み上げる文 1 つ（単語・意味・例文・例文の和訳のどれか）。
nonisolated struct ReadAloudLine: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case word
        case meaning
        case example
        case exampleJa
    }

    enum Language: Hashable, Sendable {
        case english
        case japanese
    }

    var kind: Kind
    /// 画面に出す文
    var text: String
    /// 声に出す文。日本語は「／」「〜」など読ませたくない記号を整えてある
    var spokenText: String
    /// 何番目の意味の文か（単語は 0）
    var senseIndex: Int

    var language: Language {
        switch kind {
        case .word, .example: .english
        case .meaning, .exampleJa: .japanese
        }
    }
}

/// 読み上げる語 1 つ分（文の並び）。
nonisolated struct ReadAloudItem: Hashable, Identifiable, Sendable {
    var word: WordEntry
    var lines: [ReadAloudLine]

    var id: String { word.id }
}

/// グループの単語から、読み上げる項目の並びを作る（純粋関数）。
enum ReadAloudScript {
    /// 1 語につき「単語 → 意味 → 例文 → 例文の和訳」。意味が複数あれば、単語を 1 回読んだあと意味ごとに繰り返す。
    ///
    /// 空の文は飛ばす。日本語の声が端末に無ければ（`includesJapanese == false`）日本語の文は入れない
    static func items(for words: [WordEntry], includesJapanese: Bool) -> [ReadAloudItem] {
        words.compactMap { word in
            guard let wordLine = line(.word, word.word, senseIndex: 0) else { return nil }
            var lines = [wordLine]
            for (index, sense) in word.senses.enumerated() {
                let candidates: [(ReadAloudLine.Kind, String)] = [
                    (.meaning, sense.meaning),
                    (.example, sense.example),
                    (.exampleJa, sense.exampleJa),
                ]
                lines += candidates.compactMap { kind, text in
                    line(kind, text, senseIndex: index)
                }
            }
            if !includesJapanese {
                lines.removeAll { $0.language == .japanese }
            }
            return ReadAloudItem(word: word, lines: lines)
        }
    }

    /// 穴埋めに答えたあとに読む文: 単語 → 出題した文章（1 文ずつ）。
    ///
    /// 文章は AI で作った文章で出したときはその全文、例文で出したときは出題した意味の例文。
    /// 1 文ずつに分けるのは、サーバーの 1 回の文字数の上限を超えないため
    static func fillBlankAnswerLines(for quiz: Quiz) -> [ReadAloudLine] {
        let senseIndex = quiz.word.senses.firstIndex(of: quiz.sense) ?? 0
        let text = quiz.passage?.text ?? quiz.sense.example
        let sentences = sentences(in: text).compactMap { line(.example, $0, senseIndex: senseIndex) }
        return [line(.word, quiz.word.word, senseIndex: 0)].compactMap { $0 } + sentences
    }

    /// 学習中に読む文: 単語 → 例文（例文が空なら単語だけ）。提示カード・出題・回答後・スピーカーのボタンで使う
    static func learningLines(word: String, example: String = "") -> [ReadAloudLine] {
        [line(.word, word, senseIndex: 0), line(.example, example, senseIndex: 0)].compactMap { $0 }
    }

    /// 学習で先に取っておく文: 単語 → すべての意味の例文。
    /// 出題する意味は出す直前に決まるので、どの意味で出してもすぐ鳴るように全部取る
    static func learningPrefetchLines(for word: WordEntry) -> [ReadAloudLine] {
        let examples = word.senses.enumerated().compactMap { index, sense in
            line(.example, sense.example, senseIndex: index)
        }
        return [line(.word, word.word, senseIndex: 0)].compactMap { $0 } + examples
    }

    /// 英文を文ごとに分ける（「. ! ?」のあとの空白で切る）。A1〜A2 の文章なので略語はほぼ出ない前提
    static func sentences(in text: String) -> [String] {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "([.!?][\"')\\]]*) ", with: "$1\n", options: .regularExpression)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func line(_ kind: ReadAloudLine.Kind, _ text: String, senseIndex: Int) -> ReadAloudLine? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ReadAloudLine(kind: kind, text: text, spokenText: text, senseIndex: senseIndex)
        if result.language == .japanese {
            result.spokenText = spokenJapanese(text)
        }
        guard !result.spokenText.isEmpty else { return nil }
        return result
    }

    /// 日本語の意味を声に出す形に整える。
    ///
    /// 「りんご／リンゴの木」の「／」は「スラッシュ」と読まれるので読点に、
    /// 「〜の世話をする」の「〜」は「から」と読まれるので消す。「〜の中に［で］」の［］は言い換えなので読まない
    static func spokenJapanese(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "［[^］]*］", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "／", with: "、")
        result = result.replacingOccurrences(of: "[〜～]", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
