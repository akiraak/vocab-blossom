import Charts
import SwiftData
import SwiftUI

/// 統計。学習量が「続いている」ことを実感できる粒度にとどめる。
struct StatsView: View {
    @Query private var progresses: [WordProgress]
    @Query private var logs: [AnswerLog]

    private static let chartDays = 14

    private var logSnapshots: [Dashboard.LogSnapshot] { logs.map(\.snapshot) }

    var body: some View {
        NavigationStack {
            ScrollView {
                let logSnapshots = logSnapshots
                VStack(spacing: 16) {
                    summaryCard(logSnapshots)
                    dailyChartCard(logSnapshots)
                    stageCard
                    quizTypeCard
                }
                .padding(16)
            }
            .gardenBackground()
            .navigationTitle("統計")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func summaryCard(_ logs: [Dashboard.LogSnapshot]) -> some View {
        let blossomed = progresses.count { $0.stage >= SRS.maxStage }
        let accuracy = Dashboard.accuracy(logs: logs)
        return HStack(spacing: 12) {
            metric("学習した語", "\(progresses.count)", "語")
            metric("開花", "\(blossomed)", "語")
            metric(
                "正答率",
                accuracy.map { "\(Int(($0 * 100).rounded()))" } ?? "-",
                accuracy == nil ? "" : "%"
            )
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)\(unit)")
    }

    private func dailyChartCard(_ logs: [Dashboard.LogSnapshot]) -> some View {
        let daily = Dashboard.dailyCounts(logs: logs, days: Self.chartDays, now: .now)
        let total = daily.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 10) {
            Text("この 2 週間の回答数")
                .font(.headline)
            if total == 0 {
                Text("まだ記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(daily) { item in
                    BarMark(
                        x: .value("日", item.date, unit: .day),
                        y: .value("回答", item.count)
                    )
                    .foregroundStyle(Theme.accent)
                    .cornerRadius(3)
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { value in
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        AxisTick()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .accessibilityLabel("直近 2 週間の日別回答数")
            }
            Text("合計 \(total) 問")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var stageCard: some View {
        let counts = Dictionary(grouping: progresses, by: { GrowthStage(stage: $0.stage) })
            .mapValues(\.count)
        let maxCount = max(1, counts.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("成長の内訳")
                .font(.headline)
            ForEach(GrowthStage.allCases.reversed(), id: \.self) { stage in
                if stage != .seed {
                    let count = counts[stage] ?? 0
                    HStack(spacing: 10) {
                        PlantView(stage: stage, size: 24)
                        Text(stage.label)
                            .font(.subheadline)
                            .frame(width: 56, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(stage.color)
                                .frame(
                                    width: max(2, proxy.size.width * Double(count) / Double(maxCount)),
                                    height: 10
                                )
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)
                        Text("\(count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(stage.label) \(count) 語")
                }
            }
        }
        .cardStyle()
    }

    private var quizTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("出題形式ごとの正答率")
                .font(.headline)
            ForEach(QuizType.allCases, id: \.self) { type in
                let target = graded(quizType: type)
                HStack {
                    Text(type.label)
                        .font(.subheadline)
                    Spacer()
                    if target.isEmpty {
                        Text("-")
                            .foregroundStyle(.secondary)
                    } else {
                        let rate = Double(target.count(where: \.correct)) / Double(target.count)
                        Text("\(Int((rate * 100).rounded())) %（\(target.count) 問）")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }

    /// 形式別の集計は AnswerLog を直接見る（Dashboard.LogSnapshot は形式を持たない）
    private func graded(quizType: QuizType) -> [AnswerLog] {
        logs.filter { $0.quizType == quizType && $0.kind != .requeue }
    }
}
