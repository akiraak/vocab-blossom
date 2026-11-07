import Foundation
import Testing

@testable import VocabBlossom

@Suite("ホーム・統計の集計")
struct DashboardTests {
    let now = TestDate.at(2026, 8, 14)

    private func input(
        progress: [ProgressSnapshot] = [],
        learnedAt: [String: Date] = [:],
        logs: [Dashboard.LogSnapshot] = [],
        reviewLimitPerDay: Int = 60
    ) -> Dashboard.Input {
        Dashboard.Input(
            now: now,
            progress: progress,
            learnedAtByWordId: learnedAt,
            logs: logs,
            reviewLimitPerDay: reviewLimitPerDay,
            order: .test
        )
    }

    private func log(
        _ wordId: String,
        _ dateKey: String,
        correct: Bool = true,
        kind: AnswerKind = .review
    ) -> Dashboard.LogSnapshot {
        Dashboard.LogSnapshot(wordId: wordId, dateKey: dateKey, correct: correct, kind: kind)
    }

    @Test("今日の復習は期限が来た語だけで、新しい単語は入れない（グループに入っていない語も出す）")
    func todaysReviewHasNoNewWords() {
        let yesterday = now.addingTimeInterval(-86_400)
        let tomorrow = now.addingTimeInterval(86_400)
        let progress = [
            // a1-0001 は同梱語（どのグループにも入っていなくても出す）、custom-x はマイ単語
            ProgressSnapshot(wordId: "a1-0001", stage: 2, dueAt: yesterday),
            ProgressSnapshot(wordId: "custom-x", stage: 1, dueAt: now),
            ProgressSnapshot(wordId: "a1-0002", stage: 3, dueAt: tomorrow),
        ]
        let summary = Dashboard.summary(input(progress: progress))
        #expect(Set(summary.plan.reviewWordIds) == ["a1-0001", "custom-x"])
        #expect(summary.plan.newWordIds.isEmpty)
    }

    @Test("今日こなした復習の数を 1 日の上限から引く")
    func todaysReviewsReduceTheLimit() {
        let progress = ["a", "b", "c"].map { ProgressSnapshot(wordId: $0, stage: 2, dueAt: now) }
        let logs = [
            log("x", "2026-08-14", kind: .review),
            log("y", "2026-08-14", kind: .new),
            log("y", "2026-08-14", kind: .requeue),
            log("z", "2026-08-13", kind: .review),
        ]
        let summary = Dashboard.summary(input(progress: progress, logs: logs, reviewLimitPerDay: 3))
        // 今日の復習 1 問（x）を引いて残り 2 語。残りは翌日に繰り越す
        #expect(summary.plan.reviewWordIds.count == 2)
        #expect(summary.plan.deferredReviewCount == 1)
        #expect(summary.plan.newWordIds.isEmpty)
        #expect(summary.answeredToday == 3)
    }

    @Test("ステージ別の語数と開花数を数える")
    func stageCounts() {
        let progress = [
            ProgressSnapshot(wordId: "a", stage: 1, dueAt: now),
            ProgressSnapshot(wordId: "b", stage: 1, dueAt: now),
            ProgressSnapshot(wordId: "c", stage: 4, dueAt: now),
            ProgressSnapshot(wordId: "d", stage: 5, dueAt: now),
        ]
        let summary = Dashboard.summary(input(progress: progress))
        #expect(summary.stageCounts == [1: 2, 4: 1, 5: 1])
        #expect(summary.learnedCount == 4)
        #expect(summary.blossomCount == 1)
    }

    @Test("庭は成長した順に並び、上限で打ち切られる")
    func gardenIsOrderedAndCapped() {
        let progress = (0..<80).map {
            ProgressSnapshot(wordId: "w\($0)", stage: $0 % 5 + 1, dueAt: now)
        }
        let summary = Dashboard.summary(input(progress: progress))
        #expect(summary.gardenStages.count == Dashboard.gardenCapacity)
        #expect(summary.gardenStages.first == .blossom)
        #expect(summary.learnedCount == 80)
    }

    @Test("ストリークはログの日付から求める")
    func streakFromLogs() {
        let logs = [
            log("a", "2026-08-14"), log("b", "2026-08-13"), log("c", "2026-08-12"),
            log("d", "2026-08-09"),
        ]
        #expect(Dashboard.summary(input(logs: logs)).streak == 3)
    }

    @Test("日別の回答数は空の日も 0 で埋める")
    func dailyCountsFillGaps() {
        let logs = [
            log("a", "2026-08-14"), log("b", "2026-08-14"), log("c", "2026-08-12"),
        ]
        let daily = Dashboard.dailyCounts(logs: logs, days: 4, now: now)
        #expect(daily.map(\.count) == [0, 1, 0, 2])
        #expect(daily.map { DateUtil.dateKey($0.date) }.last == "2026-08-14")
    }

    @Test("正答率は再出題を除いて計算する")
    func accuracyExcludesRequeue() {
        let logs = [
            log("a", "2026-08-14", correct: true),
            log("b", "2026-08-14", correct: false),
            log("b", "2026-08-14", correct: true, kind: .requeue),
        ]
        #expect(Dashboard.accuracy(logs: logs) == 0.5)
        #expect(Dashboard.accuracy(logs: []) == nil)
    }
}
