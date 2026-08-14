import Foundation
import SwiftData

/// 出題形式。ステージから自動で決まる（ユーザーは選ばない）。
enum QuizType: String, Codable, CaseIterable, Sendable {
    /// 英単語を見て日本語の意味を選ぶ
    case enToJa
    /// 対象語が空欄になった例文を読み、入る単語を選ぶ
    case fillBlank
    /// 日本語の意味から英単語を選ぶ
    case jaToEn
    /// 音声だけを聞いて意味を選ぶ
    case listening

    var label: String {
        switch self {
        case .enToJa: "英→日"
        case .fillBlank: "穴埋め"
        case .jaToEn: "日→英"
        case .listening: "リスニング"
        }
    }
}

/// 出題の種類。統計とストリークの集計に使う。
enum AnswerKind: String, Codable, CaseIterable, Sendable {
    /// SRS の期限が来た復習
    case review
    /// 新規学習の直後クイズ
    case new
    /// 不正解カードのセッション末尾での再出題
    case requeue
}

/// 1 回答 1 行。統計・ストリークはすべてここから導出する。
@Model
final class AnswerLog {
    var wordId: String
    var answeredAt: Date
    /// ローカル時刻の YYYY-MM-DD。日別集計・ストリークのキー
    var dateKey: String
    var correct: Bool
    var quizType: QuizType
    var kind: AnswerKind
    /// 回答後のステージ（再出題では変化しないため直前の値と同じ）
    var stageAfter: Int

    init(
        wordId: String,
        answeredAt: Date,
        dateKey: String,
        correct: Bool,
        quizType: QuizType,
        kind: AnswerKind,
        stageAfter: Int
    ) {
        self.wordId = wordId
        self.answeredAt = answeredAt
        self.dateKey = dateKey
        self.correct = correct
        self.quizType = quizType
        self.kind = kind
        self.stageAfter = stageAfter
    }
}
