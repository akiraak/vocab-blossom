import Foundation
import Testing

@testable import VocabBlossom

@Suite("日付ユーティリティ")
struct DateUtilTests {
    @Test("dateKey はローカル時刻の YYYY-MM-DD になる")
    func dateKeyFormat() {
        #expect(DateUtil.dateKey(TestDate.at(2026, 8, 14)) == "2026-08-14")
        #expect(DateUtil.dateKey(TestDate.at(2026, 1, 5, hour: 23)) == "2026-01-05")
        #expect(DateUtil.dateKey(TestDate.at(2026, 12, 31, hour: 0)) == "2026-12-31")
    }

    @Test("startOfDay はその日の 0 時に丸める")
    func startOfDayRounds() {
        let noon = TestDate.at(2026, 8, 14)
        let start = DateUtil.startOfDay(noon)
        #expect(DateUtil.dateKey(start) == "2026-08-14")
        #expect(start <= noon)
        #expect(DateUtil.startOfDay(start) == start)
    }

    @Test("addDays は月をまたいでも日付単位で進む")
    func addDaysCrossesMonth() {
        #expect(DateUtil.dateKey(DateUtil.addDays(TestDate.at(2026, 8, 30), 3)) == "2026-09-02")
        #expect(DateUtil.dateKey(DateUtil.addDays(TestDate.at(2026, 3, 1), -1)) == "2026-02-28")
        #expect(DateUtil.dateKey(DateUtil.addDays(TestDate.at(2026, 1, 15), 30)) == "2026-02-14")
    }

    @Test("daysBetween は日付単位の差を返す")
    func daysBetweenCountsCalendarDays() {
        let from = TestDate.at(2026, 8, 14, hour: 23)
        let to = TestDate.at(2026, 8, 15, hour: 1)
        #expect(DateUtil.daysBetween(from, to) == 1)
        #expect(DateUtil.daysBetween(to, from) == -1)
        #expect(DateUtil.daysBetween(from, from) == 0)
    }

    @Test("次回復習日のラベルは今日/明日/N日後/日付になる")
    func dueLabels() {
        let now = TestDate.at(2026, 8, 14)
        #expect(DateUtil.dueLabel(dueAt: DateUtil.addDays(now, -3), now: now) == "今日")
        #expect(DateUtil.dueLabel(dueAt: now, now: now) == "今日")
        #expect(DateUtil.dueLabel(dueAt: DateUtil.addDays(now, 1), now: now) == "明日")
        #expect(DateUtil.dueLabel(dueAt: DateUtil.addDays(now, 7), now: now) == "7日後")
        #expect(DateUtil.dueLabel(dueAt: DateUtil.addDays(now, 30), now: now) == "9月13日")
    }

    @Test("直近 N 日は古い順に並ぶ")
    func recentDaysAreAscending() {
        let days = DateUtil.recentDays(count: 3, from: TestDate.at(2026, 8, 14))
        #expect(days.map(DateUtil.dateKey) == ["2026-08-12", "2026-08-13", "2026-08-14"])
    }

    @Suite("ストリーク")
    struct StreakTests {
        let now = TestDate.at(2026, 8, 14)

        @Test("今日を含む連続日数を数える")
        func countsConsecutiveDaysIncludingToday() {
            let keys: Set = ["2026-08-14", "2026-08-13", "2026-08-12"]
            #expect(DateUtil.streak(dateKeys: keys, now: now) == 3)
        }

        @Test("今日まだ学習していなくても昨日まで続いていれば途切れない")
        func todayNotYetStudied() {
            let keys: Set = ["2026-08-13", "2026-08-12"]
            #expect(DateUtil.streak(dateKeys: keys, now: now) == 2)
        }

        @Test("一昨日で途切れていれば 0")
        func brokenStreak() {
            let keys: Set = ["2026-08-12", "2026-08-11"]
            #expect(DateUtil.streak(dateKeys: keys, now: now) == 0)
        }

        @Test("記録が無ければ 0")
        func noRecords() {
            #expect(DateUtil.streak(dateKeys: [], now: now) == 0)
        }

        @Test("間が空いていたら直近の連続分だけ数える")
        func gapStopsCount() {
            let keys: Set = ["2026-08-14", "2026-08-13", "2026-08-10", "2026-08-09"]
            #expect(DateUtil.streak(dateKeys: keys, now: now) == 2)
        }
    }
}
