import Foundation

/// ホーム・統計で使う集計。
///
/// SwiftData のモデルからは値だけを取り出して渡すことで、集計ロジックを単体テストできる形にする。
enum Dashboard {
    struct Summary: Equatable {
        var plan = SessionPlan()
        var streak = 0
        /// ステージ（1〜5）ごとの語数。0（種）は保存していないので含まない
        var stageCounts: [Int: Int] = [:]
        var learnedCount = 0
        var blossomCount = 0
        var answeredToday = 0

        /// 庭に咲かせる単語（開花 → つぼみ → 芽 の順、同順位は学習が新しい順）
        var gardenStages: [GrowthStage] = []
    }

    struct Input {
        var now: Date
        var progress: [ProgressSnapshot]
        /// 学習した順（庭の並びに使う）
        var learnedAtByWordId: [String: Date] = [:]
        var logs: [LogSnapshot]
        var newWordPool: [WordEntry]
        var newWordsPerDay: Int
        var reviewLimitPerDay: Int
    }

    /// AnswerLog から集計に必要な分だけ取り出した値
    struct LogSnapshot: Equatable, Sendable {
        let wordId: String
        let dateKey: String
        let correct: Bool
        let kind: AnswerKind
    }

    /// 庭に並べる最大数。数百輪を描いても見分けがつかないので上限を設ける
    static let gardenCapacity = 60

    static func summary(_ input: Input) -> Summary {
        let todayKey = DateUtil.dateKey(input.now)
        let todaysLogs = input.logs.filter { $0.dateKey == todayKey }
        let reviewsDoneToday = todaysLogs.filter { $0.kind == .review }.count
        let newWordsDoneToday = Set(
            todaysLogs.filter { $0.kind == .new }.map(\.wordId)
        ).count

        let plan = SessionBuilder.build(
            SessionBuilder.Input(
                now: input.now,
                progress: input.progress,
                newWordPool: input.newWordPool,
                newWordsPerDay: input.newWordsPerDay,
                reviewLimitPerDay: input.reviewLimitPerDay,
                reviewsDoneToday: reviewsDoneToday,
                newWordsDoneToday: newWordsDoneToday
            )
        )

        var summary = Summary()
        summary.plan = plan
        summary.streak = DateUtil.streak(dateKeys: Set(input.logs.map(\.dateKey)), now: input.now)
        summary.stageCounts = Dictionary(
            grouping: input.progress, by: \.stage
        ).mapValues(\.count)
        summary.learnedCount = input.progress.count
        summary.blossomCount = input.progress.filter { $0.stage >= SRS.maxStage }.count
        summary.answeredToday = todaysLogs.count

        let ordered = input.progress.sorted {
            if $0.stage != $1.stage { return $0.stage > $1.stage }
            let left = input.learnedAtByWordId[$0.wordId] ?? .distantPast
            let right = input.learnedAtByWordId[$1.wordId] ?? .distantPast
            return left > right
        }
        summary.gardenStages = ordered.prefix(gardenCapacity).map { GrowthStage(stage: $0.stage) }
        return summary
    }

    /// 直近 `days` 日の日別回答数（古い順）
    static func dailyCounts(logs: [LogSnapshot], days: Int, now: Date) -> [(date: Date, count: Int)] {
        var counts: [String: Int] = [:]
        for log in logs { counts[log.dateKey, default: 0] += 1 }
        return DateUtil.recentDays(count: days, from: now).map {
            (date: $0, count: counts[DateUtil.dateKey($0)] ?? 0)
        }
    }

    /// 正答率（再出題は除く。復習・新規の初回回答だけを見る）
    static func accuracy(logs: [LogSnapshot]) -> Double? {
        let graded = logs.filter { $0.kind != .requeue }
        guard !graded.isEmpty else { return nil }
        return Double(graded.filter(\.correct).count) / Double(graded.count)
    }
}
