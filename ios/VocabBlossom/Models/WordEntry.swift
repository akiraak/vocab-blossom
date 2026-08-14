import Foundation

/// 収録レベル（CEFR）。新規学習の出題範囲を決める。
enum CefrLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"

    var id: String { rawValue }

    var label: String { rawValue }

    var summary: String {
        switch self {
        case .a1: "中学基礎レベル（はじめての人向け）"
        case .a2: "中学卒業〜高校基礎レベル"
        }
    }
}

/// 品詞。誤答肢を同じ品詞から選ぶために使う。
enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
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

/// 単語 1 件。`data/decks/*.json` のエントリと 1:1 で対応する。
struct WordEntry: Codable, Hashable, Identifiable, Sendable {
    /// レベル別連番（例: "a1-0001"）。学習進捗のキーになるため不変。
    let id: String
    let word: String
    let pos: PartOfSpeech
    let level: CefrLevel
    /// 日本語の意味。複数は「／」区切りで 2 個まで。
    let meaning: String
    let example: String
    let exampleJa: String
}

/// デッキ 1 つ（JSON ファイル 1 つ）。
struct Deck: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let words: [WordEntry]
}
