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
    /// 2 つ目以降の意味（`[WordSense]` の JSON）。nil は無し。`extraSenses` で読み書きする
    var extraSensesData: Data?
    var createdAt: Date
    var updatedAt: Date
    /// サーバーと一致していると分かっている `updatedAt`。`updatedAt` と違えば次の同期で送る（nil は未送信）
    var syncedUpdatedAt: Date?

    init(
        wordId: String = CustomWord.makeId(),
        word: String,
        meaning: String,
        pos: PartOfSpeech,
        example: String = "",
        exampleJa: String = "",
        extraSenses: [WordSense] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.wordId = wordId
        self.word = word
        self.meaning = meaning
        self.pos = pos
        self.example = example
        self.exampleJa = exampleJa
        self.extraSensesData = WordSense.encodeList(extraSenses)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 2 つ目以降の意味（品詞の違う意味）
    var extraSenses: [WordSense] {
        get { WordSense.decodeList(extraSensesData) }
        set { extraSensesData = WordSense.encodeList(newValue) }
    }

    static func makeId() -> String {
        idPrefix + UUID().uuidString.lowercased()
    }

    static func isCustom(_ wordId: String) -> Bool {
        wordId.hasPrefix(idPrefix)
    }

    /// 前回の同期のあとに手元で変わった
    var needsSync: Bool {
        syncedUpdatedAt?.syncMillis != updatedAt.syncMillis
    }

    var entry: WordEntry {
        WordEntry(
            id: wordId,
            word: word,
            pos: pos,
            level: nil,
            meaning: meaning,
            example: example,
            exampleJa: exampleJa,
            extraSenses: extraSenses
        )
    }
}
