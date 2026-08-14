import Foundation
import Testing

@testable import VocabBlossom

@Suite("SRS（Leitner）")
struct SRSTests {
    let now = TestDate.at(2026, 8, 14)

    private func daysUntil(_ result: SRS.Result) -> Int {
        DateUtil.daysBetween(now, result.dueAt)
    }

    @Test(
        "正解でステージが 1 つ上がり、間隔が 1日→3日→1週→2週→1ヶ月と伸びる",
        arguments: [(0, 1, 1), (1, 2, 3), (2, 3, 7), (3, 4, 14), (4, 5, 30)]
    )
    func correctAdvancesStage(prev: Int, expectedStage: Int, expectedDays: Int) {
        let result = SRS.applyAnswer(prevStage: prev, correct: true, now: now)
        #expect(result.stage == expectedStage)
        #expect(daysUntil(result) == expectedDays)
    }

    @Test("開花後に正解しても 5 のまま、維持間隔は 3 ヶ月")
    func blossomStaysAtMaxWithMaintenanceInterval() {
        let result = SRS.applyAnswer(prevStage: 5, correct: true, now: now)
        #expect(result.stage == 5)
        #expect(daysUntil(result) == 90)
    }

    @Test("不正解でステージが 1 つ下がり、翌日に再スケジュールされる")
    func incorrectDropsStage() {
        for prev in 2...5 {
            let result = SRS.applyAnswer(prevStage: prev, correct: false, now: now)
            #expect(result.stage == prev - 1)
            #expect(daysUntil(result) == 1)
        }
    }

    @Test("不正解でも芽（1）より下がらない")
    func incorrectNeverGoesBelowSprout() {
        for prev in [0, 1] {
            let result = SRS.applyAnswer(prevStage: prev, correct: false, now: now)
            #expect(result.stage == SRS.minLearnedStage)
            #expect(daysUntil(result) == 1)
        }
    }

    @Test("次回復習日は 0 時に丸められる")
    func dueAtIsStartOfDay() {
        let result = SRS.applyAnswer(prevStage: 1, correct: true, now: now)
        #expect(result.dueAt == DateUtil.startOfDay(result.dueAt))
    }

    @Test("「もう知ってる」は開花（5）・約 3 ヶ月後の維持復習のみ")
    func knownJumpsToBlossom() {
        let result = SRS.applyKnown(now: now)
        #expect(result.stage == SRS.maxStage)
        #expect(daysUntil(result) == 90)
    }

    @Test(
        "出題形式はステージに連動する",
        arguments: [
            (0, QuizType.enToJa), (1, .enToJa), (2, .enToJa),
            (3, .fillBlank), (4, .jaToEn), (5, .listening), (6, .listening),
        ]
    )
    func quizTypeFollowsStage(stage: Int, expected: QuizType) {
        #expect(SRS.quizType(for: stage) == expected)
    }

    @Test("成長段階は 種/芽/つぼみ/開花 に分かれる")
    func growthStages() {
        #expect(GrowthStage(stage: 0) == .seed)
        #expect(GrowthStage(stage: 1) == .sprout)
        #expect(GrowthStage(stage: 2) == .sprout)
        #expect(GrowthStage(stage: 3) == .bud)
        #expect(GrowthStage(stage: 4) == .bud)
        #expect(GrowthStage(stage: 5) == .blossom)
    }
}
