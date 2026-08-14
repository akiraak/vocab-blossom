import Foundation
import SwiftData

/// 単語ごとの学習進捗。
///
/// **レコードが無い単語 = 種（stage 0、未学習）**として扱い、未学習語のレコードは作らない。
/// そのため 2,443 語すべてを保存する必要がなく、学習した語だけが並ぶ。
@Model
final class WordProgress {
    /// `WordEntry.id`
    @Attribute(.unique) var wordId: String
    /// 1(芽) 〜 5(開花)。0 のレコードは作らない
    var stage: Int
    /// 次回復習日（その日の 0 時）
    var dueAt: Date
    /// 初めて学習した日時
    var learnedAt: Date
    var updatedAt: Date
    /// 「もう知ってる」で登録されたか
    var known: Bool

    init(
        wordId: String,
        stage: Int,
        dueAt: Date,
        learnedAt: Date,
        updatedAt: Date,
        known: Bool = false
    ) {
        self.wordId = wordId
        self.stage = stage
        self.dueAt = dueAt
        self.learnedAt = learnedAt
        self.updatedAt = updatedAt
        self.known = known
    }
}
