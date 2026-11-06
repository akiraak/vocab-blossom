import Foundation
import SwiftData

/// グループのどの入口から答えたか
enum GroupAnswerSource: String, Codable, CaseIterable, Sendable {
    /// グループの「学習する」（SRS に記録する学習）
    case learning
    /// グループのドリル（進捗を動かさない）
    case drill
    /// グループの穴埋めモード（進捗を動かさない）
    case fillBlank
}

/// どのグループのどの入口から始めたか。回答を `GroupAnswerLog` に残すのに使う
struct GroupAnswerContext: Equatable {
    var groupId: UUID
    var source: GroupAnswerSource
}

/// グループの問題に答えた記録。1 回答 1 行。グループ一覧の回答数・達成度はここから数える。
///
/// `AnswerLog`（統計・ストリーク・SRS の元）とは別に持つ。ドリル・穴埋めの回答を `AnswerLog` に混ぜると、
/// 今の集計すべてで除外が要るため。グループの「学習する」の回答は両方に書く。
/// 同期はしない（端末だけ）。バックアップには入れる。
@Model
final class GroupAnswerLog {
    /// `WordGroup.id`（サーバーと同じ ID）
    var groupId: UUID
    var wordId: String
    var answeredAt: Date
    var correct: Bool
    var quizType: QuizType
    var source: GroupAnswerSource
    var kind: AnswerKind

    init(
        groupId: UUID,
        wordId: String,
        answeredAt: Date,
        correct: Bool,
        quizType: QuizType,
        source: GroupAnswerSource,
        kind: AnswerKind
    ) {
        self.groupId = groupId
        self.wordId = wordId
        self.answeredAt = answeredAt
        self.correct = correct
        self.quizType = quizType
        self.source = source
        self.kind = kind
    }

    var snapshot: GroupStudy.Answer {
        GroupStudy.Answer(wordId: wordId, answeredAt: answeredAt, correct: correct)
    }

    /// グループを消したときに、そのグループの記録も消す
    static func purge(groupId: UUID, in context: ModelContext) {
        try? context.delete(model: GroupAnswerLog.self, where: #Predicate { $0.groupId == groupId })
    }
}
