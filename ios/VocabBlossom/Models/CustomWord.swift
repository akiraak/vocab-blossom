import Foundation
import SwiftData

/// ユーザーが自分で登録した単語・フレーズ。
///
/// `entry` で `WordEntry` に変換し、以降はセッション・クイズ・単語詳細で同梱語と同じように扱う。
@Model
final class CustomWord {
    static let idPrefix = "custom-"

    /// `WordEntry.id`。同梱語と衝突しないよう `custom-` で始める
    @Attribute(.unique) var wordId: String
    var word: String
    var meaning: String
    var pos: PartOfSpeech
    /// 例文は任意（空文字なら穴埋め問題にはならず、例文も表示しない）
    var example: String
    var exampleJa: String
    var createdAt: Date
    var updatedAt: Date

    init(
        wordId: String = CustomWord.makeId(),
        word: String,
        meaning: String,
        pos: PartOfSpeech,
        example: String = "",
        exampleJa: String = "",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.wordId = wordId
        self.word = word
        self.meaning = meaning
        self.pos = pos
        self.example = example
        self.exampleJa = exampleJa
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func makeId() -> String {
        idPrefix + UUID().uuidString.lowercased()
    }

    static func isCustom(_ wordId: String) -> Bool {
        wordId.hasPrefix(idPrefix)
    }

    var entry: WordEntry {
        WordEntry(
            id: wordId,
            word: word,
            pos: pos,
            level: nil,
            meaning: meaning,
            example: example,
            exampleJa: exampleJa
        )
    }
}
