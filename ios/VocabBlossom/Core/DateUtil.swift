import Foundation

/// 日付の扱いを 1 か所にまとめる。
///
/// 復習スケジュールは「日」単位なので、比較・加算はすべて `Calendar` 経由で行い、
/// DST やタイムゾーンで 1 日ずれないようにする。
enum DateUtil {
    static var calendar: Calendar { Calendar.current }

    /// その日の 0 時（ローカル時刻）
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 日付をまたぐ加算
    static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// 進捗ログのキーに使う YYYY-MM-DD（ローカル時刻）
    static func dateKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// from → to の日数差（日付単位）。to が未来なら正
    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    /// 次回復習日の表示用ラベル
    static func dueLabel(dueAt: Date, now: Date) -> String {
        let diff = daysBetween(now, dueAt)
        if diff <= 0 { return "今日" }
        if diff == 1 { return "明日" }
        if diff < 30 { return "\(diff)日後" }
        return formatMonthDay(dueAt)
    }

    static func formatMonthDay(_ date: Date) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    static func formatDate(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)/\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    /// 直近 `count` 日分の日付（古い順）。統計の日別グラフに使う
    static func recentDays(count: Int, from now: Date) -> [Date] {
        let today = startOfDay(now)
        return (0..<count).reversed().map { addDays(today, -$0) }
    }

    /// 回答があった日（YYYY-MM-DD）の集合から連続学習日数を求める。
    ///
    /// 今日まだ学習していなくても、昨日まで続いていればストリークは途切れていない扱いにする。
    static func streak(dateKeys: Set<String>, now: Date) -> Int {
        let today = startOfDay(now)
        var cursor = dateKeys.contains(dateKey(today)) ? today : addDays(today, -1)
        guard dateKeys.contains(dateKey(cursor)) else { return 0 }
        var count = 0
        while dateKeys.contains(dateKey(cursor)) {
            count += 1
            cursor = addDays(cursor, -1)
        }
        return count
    }
}
