import SwiftData
import SwiftUI

/// ホーム（庭）。咲いた花・ストリーク・今日の学習ボタンをまとめる。
struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var progresses: [WordProgress]
    @Query private var logs: [AnswerLog]

    @State private var isSessionPresented = false

    private let store = WordStore.shared

    private var summary: Dashboard.Summary {
        Dashboard.summary(
            Dashboard.Input(
                now: .now,
                progress: progresses.map(\.snapshot),
                learnedAtByWordId: Dictionary(
                    progresses.map { ($0.wordId, $0.learnedAt) },
                    uniquingKeysWith: { first, _ in first }
                ),
                logs: logs.map(\.snapshot),
                newWordPool: store.newWordPool(level: settings.level),
                newWordsPerDay: settings.newWordsPerDay,
                reviewLimitPerDay: settings.reviewLimitPerDay
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let summary = summary
                VStack(spacing: 16) {
                    gardenCard(summary)
                    statsRow(summary)
                    todayCard(summary)
                }
                .padding(16)
            }
            .gardenBackground()
            .navigationTitle("vocab-blossom")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $isSessionPresented) {
                SessionView(plan: summary.plan)
            }
        }
    }

    private func gardenCard(_ summary: Dashboard.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("あなたの庭")
                .font(.headline)
            GardenView(
                stages: summary.gardenStages,
                overflow: max(0, summary.learnedCount - summary.gardenStages.count)
            )
            HStack(spacing: 12) {
                ForEach(GrowthStage.allCases.reversed(), id: \.self) { stage in
                    if stage != .seed {
                        stageChip(stage, count: count(of: stage, in: summary))
                    }
                }
            }
        }
        .cardStyle()
    }

    private func stageChip(_ stage: GrowthStage, count: Int) -> some View {
        HStack(spacing: 4) {
            PlantView(stage: stage, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(stage.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.label) \(count) 語")
    }

    private func count(of stage: GrowthStage, in summary: Dashboard.Summary) -> Int {
        summary.stageCounts
            .filter { GrowthStage(stage: $0.key) == stage }
            .values
            .reduce(0, +)
    }

    private func statsRow(_ summary: Dashboard.Summary) -> some View {
        HStack(spacing: 12) {
            metric(title: "ストリーク", value: "\(summary.streak)", unit: "日", symbol: "flame.fill")
            metric(title: "覚えた語", value: "\(summary.learnedCount)", unit: "語", symbol: "leaf.fill")
            metric(title: "今日の回答", value: "\(summary.answeredToday)", unit: "問", symbol: "checkmark.circle.fill")
        }
    }

    private func metric(title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
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

    private func todayCard(_ summary: Dashboard.Summary) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("今日の学習")
                    .font(.headline)
                Spacer()
                Text(settings.level.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }

            if summary.plan.isEmpty {
                Label("今日の分は終わりました。また明日！", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.correct)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 20) {
                    countLabel("復習", summary.plan.reviewWordIds.count)
                    countLabel("新しい単語", summary.plan.newWordIds.count)
                    Spacer()
                }
            }

            if summary.plan.deferredReviewCount > 0 {
                Text("復習が \(summary.plan.deferredReviewCount) 語たまっています。今日の分から少しずつ進めましょう。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                isSessionPresented = true
            } label: {
                Text(summary.plan.isEmpty ? "今日の分は完了" : "はじめる（\(summary.plan.totalCount) 語）")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(summary.plan.isEmpty)
        }
        .cardStyle()
    }

    private func countLabel(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(count) 語")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(count) 語")
    }
}
