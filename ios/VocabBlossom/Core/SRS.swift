import Foundation

/// 間隔反復（Leitner 方式）。
///
/// 初学者向けなので FSRS / SM-2 のような複雑なアルゴリズムは使わず、
/// ステージ固定の間隔で「1日 → 3日 → 1週間 → 2週間 → 1ヶ月 → 開花」と伸ばす。
enum SRS {
    static let maxStage = 5
    /// 一度学習した単語はここより下がらない（芽）
    static let minLearnedStage = 1
    /// 「もう知ってる」で押し上げるステージ。既知語で席を埋めないよう、いきなり開花にする
    static let knownStage = maxStage
    /// 同一カードをセッション末尾で再出題する上限
    static let maxRequeue = 2

    /// ステージに到達したときの次回復習までの日数
    private static let intervalByStage: [Int: Int] = [1: 1, 2: 3, 3: 7, 4: 14, 5: 30]
    /// 開花済みの単語を再度正解したときの維持間隔
    private static let maintenanceDays = 90

    struct Result: Equatable {
        var stage: Int
        var dueAt: Date
    }

    static func intervalDays(from prevStage: Int, to nextStage: Int) -> Int {
        if nextStage == maxStage, prevStage == maxStage { return maintenanceDays }
        return intervalByStage[nextStage] ?? 1
    }

    /// 回答結果からステージと次回復習日を求める。
    ///
    /// 未学習（stage 0）で不正解でも芽（1）にして翌日の復習に乗せる。
    static func applyAnswer(prevStage: Int, correct: Bool, now: Date) -> Result {
        guard correct else {
            let stage = max(prevStage - 1, minLearnedStage)
            return Result(stage: stage, dueAt: DateUtil.startOfDay(DateUtil.addDays(now, 1)))
        }
        let stage = min(prevStage + 1, maxStage)
        let days = intervalDays(from: prevStage, to: stage)
        return Result(stage: stage, dueAt: DateUtil.startOfDay(DateUtil.addDays(now, days)))
    }

    /// 「もう知ってる」を押されたとき。
    ///
    /// 既知語で席を埋めないことが目的なので、開花済みと同じ扱いにして次回は
    /// 維持復習（約 3 ヶ月後）まで出さない。数百語まとめて登録しても復習が雪崩れない。
    static func applyKnown(now: Date) -> Result {
        let days = intervalDays(from: knownStage, to: knownStage)
        return Result(stage: knownStage, dueAt: DateUtil.startOfDay(DateUtil.addDays(now, days)))
    }

    /// ステージに応じた出題形式。「見て分かる → 文脈で分かる → 思い出せる → 聞いて分かる」と進む
    static func quizType(for stage: Int) -> QuizType {
        switch stage {
        case ..<3: .enToJa
        case 3: .fillBlank
        case 4: .jaToEn
        default: .listening
        }
    }
}
