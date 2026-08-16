import Foundation
import Testing

@testable import VocabBlossom

@Suite("セッション構築")
struct SessionBuilderTests {
    let now = TestDate.at(2026, 8, 14)
    let pool = WordStore.shared.newWordPool(level: .a1, order: .test)

    private func input(
        progress: [ProgressSnapshot] = [],
        newWordsPerDay: Int = 10,
        reviewLimitPerDay: Int = 60,
        reviewsDoneToday: Int = 0,
        newWordsDoneToday: Int = 0
    ) -> SessionBuilder.Input {
        SessionBuilder.Input(
            now: now,
            progress: progress,
            newWordPool: pool,
            newWordsPerDay: newWordsPerDay,
            reviewLimitPerDay: reviewLimitPerDay,
            reviewsDoneToday: reviewsDoneToday,
            newWordsDoneToday: newWordsDoneToday,
            order: .test
        )
    }

    /// `offsets` の日数だけ期限がずれた進捗を作る（負なら期限超過）
    private func progress(dueOffsets offsets: [Int], stage: Int = 2) -> [ProgressSnapshot] {
        offsets.enumerated().map { index, offset in
            ProgressSnapshot(
                wordId: String(format: "w-%04d", index),
                stage: stage,
                dueAt: DateUtil.startOfDay(DateUtil.addDays(now, offset))
            )
        }
    }

    @Test("期限が来た単語だけ復習に入る")
    func onlyDueWordsAreReviewed() {
        let plan = SessionBuilder.build(input(progress: progress(dueOffsets: [-2, 0, 1, 5])))
        #expect(Set(plan.reviewWordIds) == ["w-0000", "w-0001"])
        #expect(plan.deferredReviewCount == 0)
    }

    @Test("上限で打ち切るときは期限超過の古い方から選ぶ")
    func mostOverdueSurviveTheLimit() {
        let items = progress(dueOffsets: [0, -5, -1])
        let plan = SessionBuilder.build(input(progress: items, reviewLimitPerDay: 2))
        #expect(Set(plan.reviewWordIds) == ["w-0001", "w-0002"])
        #expect(plan.deferredReviewCount == 1)
    }

    @Test("出題順は ID 順にならない（毎日同じ並びで覚えないように）")
    func reviewOrderIsShuffled() {
        let items = progress(dueOffsets: Array(repeating: -1, count: 30))
        let plan = SessionBuilder.build(input(progress: items))
        #expect(Set(plan.reviewWordIds) == Set(items.map(\.wordId)))
        #expect(plan.reviewWordIds != items.map(\.wordId))
    }

    @Test("復習は 1 日上限までで打ち切り、残りは翌日へ繰り越す")
    func reviewLimitDefersRest() {
        let items = progress(dueOffsets: Array(repeating: -1, count: 80))
        let plan = SessionBuilder.build(input(progress: items, reviewLimitPerDay: 60))
        #expect(plan.reviewWordIds.count == 60)
        #expect(plan.deferredReviewCount == 20)
    }

    @Test("同じ日に再開しても、今日こなした分だけ上限が減る")
    func alreadyDoneReviewsConsumeTheLimit() {
        let items = progress(dueOffsets: Array(repeating: -1, count: 80))
        let plan = SessionBuilder.build(
            input(progress: items, reviewLimitPerDay: 60, reviewsDoneToday: 55)
        )
        #expect(plan.reviewWordIds.count == 5)
        #expect(plan.deferredReviewCount == 75)
    }

    @Test("新規語は未学習の語から設定数だけ、プールの順で出す")
    func newWordsComeFromUnlearnedPool() {
        let plan = SessionBuilder.build(input(newWordsPerDay: 10))
        #expect(plan.newWordIds.count == 10)
        #expect(plan.newWordIds == pool.prefix(10).map(\.id))
    }

    @Test("学習済みの語は新規学習に出さない")
    func learnedWordsAreExcluded() {
        let learned = pool.prefix(3).map {
            ProgressSnapshot(
                wordId: $0.id, stage: 3, dueAt: DateUtil.addDays(now, 5)
            )
        }
        let plan = SessionBuilder.build(input(progress: Array(learned), newWordsPerDay: 5))
        #expect(plan.newWordIds == pool.dropFirst(3).prefix(5).map(\.id))
        #expect(plan.reviewWordIds.isEmpty)
    }

    @Test("復習が上限を超えている日は新規語を出さない")
    func newWordsAreSuppressedWhenReviewsPileUp() {
        let items = progress(dueOffsets: Array(repeating: -1, count: 61))
        let plan = SessionBuilder.build(input(progress: items, reviewLimitPerDay: 60))
        #expect(plan.reviewWordIds.count == 60)
        #expect(plan.newWordIds.isEmpty)
    }

    @Test("上限ちょうどなら新規語は出る")
    func newWordsSurviveAtExactlyTheLimit() {
        let items = progress(dueOffsets: Array(repeating: -1, count: 60))
        let plan = SessionBuilder.build(input(progress: items, reviewLimitPerDay: 60))
        #expect(plan.newWordIds.count == 10)
    }

    @Test("今日すでに学習した新規語の分だけ残りが減る")
    func newWordsAlreadyLearnedTodayReduceTheQuota() {
        let plan = SessionBuilder.build(input(newWordsPerDay: 10, newWordsDoneToday: 7))
        #expect(plan.newWordIds.count == 3)

        let done = SessionBuilder.build(input(newWordsPerDay: 10, newWordsDoneToday: 10))
        #expect(done.newWordIds.isEmpty)
    }

    @Test("何も無ければ空のプラン")
    func emptyPlan() {
        let plan = SessionBuilder.build(input(newWordsPerDay: 0))
        #expect(plan.isEmpty)
        #expect(plan.totalCount == 0)
    }

    @Test("新規 50 語/日でも、自動追従した復習上限なら定常状態で新規語が止まらない")
    func newWordsSurviveSteadyStateAtFiftyPerDay() {
        let newWordsPerDay = 50
        let reviewLimit = AppSettings.reviewLimit(forNewWordsPerDay: newWordsPerDay)
        // 定常状態では 1 語が開花までに 5 回戻ってくるので、期限到来は約 新規語 × 5
        let steadyStateDue = newWordsPerDay * 5
        let items = progress(dueOffsets: Array(repeating: -1, count: steadyStateDue))

        let plan = SessionBuilder.build(
            input(
                progress: items,
                newWordsPerDay: newWordsPerDay,
                reviewLimitPerDay: reviewLimit
            )
        )
        #expect(plan.reviewWordIds.count == steadyStateDue)
        #expect(plan.deferredReviewCount == 0)
        #expect(plan.newWordIds.count == newWordsPerDay)
    }

    @Test("新規語は 5 語ずつのミニバッチに割れる")
    func newWordsSplitIntoBatches() {
        let plan = SessionBuilder.build(input(newWordsPerDay: 12))
        #expect(plan.newBatches.map(\.count) == [5, 5, 2])
        #expect(plan.newBatches.flatMap { $0 } == plan.newWordIds)
    }
}
