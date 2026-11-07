import Foundation

/// 収録レベル（CEFR）。誤答肢を同じレベルから選ぶのと、単語詳細の表示に使う。
enum CefrLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"

    var id: String { rawValue }

    var label: String { rawValue }
}

/// 品詞。誤答肢を同じ品詞から選ぶために使う。
nonisolated enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun, verb, adjective, adverb, preposition, conjunction
    case interjection, number, determiner, pronoun, modal, phrase

    var label: String {
        switch self {
        case .noun: "名詞"
        case .verb: "動詞"
        case .adjective: "形容詞"
        case .adverb: "副詞"
        case .preposition: "前置詞"
        case .conjunction: "接続詞"
        case .interjection: "間投詞"
        case .number: "数詞"
        case .determiner: "限定詞"
        case .pronoun: "代名詞"
        case .modal: "助動詞"
        case .phrase: "熟語"
        }
    }
}

/// 単語の意味 1 つ分（品詞・意味・例文・例文の訳）。
///
/// commute の「動詞: 通勤する」「名詞: 通勤」のように、1 語が品詞の違う意味を複数持てる（いまは自作語だけ）
nonisolated struct WordSense: Codable, Hashable, Sendable {
    var pos: PartOfSpeech
    var meaning: String
    /// 例文は任意（空文字なら穴埋め問題にはならず、例文も表示しない）
    var example: String
    var exampleJa: String

    init(pos: PartOfSpeech, meaning: String, example: String = "", exampleJa: String = "") {
        self.pos = pos
        self.meaning = meaning
        self.example = example
        self.exampleJa = exampleJa
    }

    /// 自作語の 2 つ目以降の意味の保存・同期用（無い・読めないなら空）
    static func decodeList(_ data: Data?) -> [WordSense] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([WordSense].self, from: data)) ?? []
    }

    static func encodeList(_ senses: [WordSense]) -> Data? {
        senses.isEmpty ? nil : try? JSONEncoder().encode(senses)
    }
}

/// 単語 1 件。`data/decks/*.json` のエントリと 1:1 で対応する。
/// ユーザーの自作語（`CustomWord`）もこの形に変換して同じ経路で扱う。
///
/// `pos`・`meaning`・`example`・`exampleJa` は 1 つ目の意味。2 つ目以降は `extraSenses`（同梱語は常に空）
nonisolated struct WordEntry: Codable, Hashable, Identifiable, Sendable {
    /// レベル別連番（例: "a1-0001"）。自作語は "custom-<uuid>"。学習進捗のキーになるため不変。
    let id: String
    let word: String
    let pos: PartOfSpeech
    /// 同梱語は必ず入る。自作語は nil
    let level: CefrLevel?
    /// 日本語の意味。複数は「／」区切りで 2 個まで。
    let meaning: String
    let example: String
    let exampleJa: String
    /// 2 つ目以降の意味（品詞の違う意味）。同梱語のデータには無いので空
    let extraSenses: [WordSense]

    init(
        id: String,
        word: String,
        pos: PartOfSpeech,
        level: CefrLevel?,
        meaning: String,
        example: String,
        exampleJa: String,
        extraSenses: [WordSense] = []
    ) {
        self.id = id
        self.word = word
        self.pos = pos
        self.level = level
        self.meaning = meaning
        self.example = example
        self.exampleJa = exampleJa
        self.extraSenses = extraSenses
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, pos, level, meaning, example, exampleJa, extraSenses
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            word: try container.decode(String.self, forKey: .word),
            pos: try container.decode(PartOfSpeech.self, forKey: .pos),
            level: try container.decodeIfPresent(CefrLevel.self, forKey: .level),
            meaning: try container.decode(String.self, forKey: .meaning),
            example: try container.decode(String.self, forKey: .example),
            exampleJa: try container.decode(String.self, forKey: .exampleJa),
            extraSenses: try container.decodeIfPresent([WordSense].self, forKey: .extraSenses) ?? []
        )
    }

    var isCustom: Bool { level == nil }

    /// 1 つ目の意味
    var primarySense: WordSense {
        WordSense(pos: pos, meaning: meaning, example: example, exampleJa: exampleJa)
    }

    /// すべての意味（1 つ目 + 2 つ目以降）
    var senses: [WordSense] { [primarySense] + extraSenses }

    /// その品詞の意味（無ければ 1 つ目の意味）。誤答肢に出す意味を、出題する意味の品詞に合わせるのに使う
    func sense(for pos: PartOfSpeech) -> WordSense {
        senses.first { $0.pos == pos } ?? primarySense
    }

    /// 一覧の 1 行に出す意味。意味が 1 つならそのまま、複数なら「動詞: 通勤する／名詞: 通勤」
    var meaningSummary: String {
        guard !extraSenses.isEmpty else { return meaning }
        return senses.map { "\($0.pos.label): \($0.meaning)" }.joined(separator: "／")
    }
}

/// デッキ 1 つ（JSON ファイル 1 つ）。
struct Deck: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let words: [WordEntry]
}
