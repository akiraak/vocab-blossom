import Foundation

/// ホーム・統計で使う集計。
///
/// SwiftData のモデルからは値だけを取り出して渡すことで、集計ロジックを単体テストできる形にする。
enum Dashboard {
    struct Summary: Equatable {
        /// 今日の復習（期限が来た語。新しい単語は入れない。新しい単語はグループの「学習する」で始める）
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
        var reviewLimitPerDay: Int
        /// 出題順をランダムにする並び
        var order: ShuffleOrder = .install
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

        // 学習を始めた語（グループに入っていない語も）の、期限が来た復習だけ
        let plan = SessionBuilder.build(
            SessionBuilder.Input(
                now: input.now,
                progress: input.progress,
                newWordPool: [],
                newWordsPerDay: 0,
                reviewLimitPerDay: input.reviewLimitPerDay,
                reviewsDoneToday: reviewsDoneToday,
                order: input.order
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

        summary.gardenStages = gardenStages(
            progress: input.progress, learnedAtByWordId: input.learnedAtByWordId
        )
        return summary
    }

    /// 庭に並べる植物。育った順・同じなら最近始めた順に、庭に入る数まで
    static func gardenStages(
        progress: [ProgressSnapshot],
        learnedAtByWordId: [String: Date]
    ) -> [GrowthStage] {
        let ordered = progress.sorted {
            if $0.stage != $1.stage { return $0.stage > $1.stage }
            let left = learnedAtByWordId[$0.wordId] ?? .distantPast
            let right = learnedAtByWordId[$1.wordId] ?? .distantPast
            return left > right
        }
        return ordered.prefix(gardenCapacity).map { GrowthStage(stage: $0.stage) }
    }

    struct DailyCount: Identifiable, Equatable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    /// 直近 `days` 日の日別回答数（古い順）
    static func dailyCounts(logs: [LogSnapshot], days: Int, now: Date) -> [DailyCount] {
        var counts: [String: Int] = [:]
        for log in logs { counts[log.dateKey, default: 0] += 1 }
        return DateUtil.recentDays(count: days, from: now).map {
            DailyCount(date: $0, count: counts[DateUtil.dateKey($0)] ?? 0)
        }
    }

    /// 正答率（再出題は除く。復習・新規の初回回答だけを見る）
    static func accuracy(logs: [LogSnapshot]) -> Double? {
        let graded = logs.filter { $0.kind != .requeue }
        guard !graded.isEmpty else { return nil }
        return Double(graded.filter(\.correct).count) / Double(graded.count)
    }
}
