import SwiftData
import SwiftUI

/// 単語詳細。意味・例文・音声に加えて、成長状態と回答履歴を見せる。
struct WordDetailView: View {
    let word: WordEntry

    @Query private var progresses: [WordProgress]
    @Query private var logs: [AnswerLog]

    init(word: WordEntry) {
        self.word = word
        let wordId = word.id
        _progresses = Query(filter: #Predicate<WordProgress> { $0.wordId == wordId })
        _logs = Query(
            filter: #Predicate<AnswerLog> { $0.wordId == wordId },
            sort: [SortDescriptor(\AnswerLog.answeredAt, order: .reverse)]
        )
    }

    private var progress: WordProgress? { progresses.first }
    private var stage: Int { progress?.stage ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WordCardView(word: word)
                    .cardStyle()
                statusCard
                if !logs.isEmpty {
                    historyCard
                }
            }
            .padding(16)
        }
        .gardenBackground()
        .navigationTitle(word.word)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PlantView(stage: GrowthStage(stage: stage), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GrowthStage(stage: stage).label)
                        .font(.headline)
                    Text(stage == 0 ? "まだ学習していません" : "ステージ \(stage) / \(SRS.maxStage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let progress {
                Divider()
                row("次回の復習", DateUtil.dueLabel(dueAt: progress.dueAt, now: .now))
                row("学習を始めた日", DateUtil.formatDate(progress.learnedAt))
                if progress.known {
                    row("登録", "「もう知ってる」から")
                }
            }

            if let deck = WordStore.shared.deck(of: word.id) {
                Divider()
                row("デッキ", deck.name)
                row("レベル", word.level.label)
            }
        }
        .cardStyle()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("回答履歴")
                .font(.headline)
            ForEach(logs.prefix(20)) { log in
                HStack(spacing: 10) {
                    Image(systemName: log.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(log.correct ? Theme.correct : Theme.incorrect)
                    Text(DateUtil.formatDate(log.answeredAt))
                        .font(.caption)
                        .monospacedDigit()
                    Text(log.quizType.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    Spacer()
                    if log.kind == .requeue {
                        Text("再出題")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if logs.count > 20 {
                Text("ほか \(logs.count - 20) 件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}
