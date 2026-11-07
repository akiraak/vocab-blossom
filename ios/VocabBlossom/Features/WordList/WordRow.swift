import SwiftUI

/// 単語一覧の 1 行（グループ詳細・マイ単語）。成長状態と次回復習日をひと目で分かるようにする。
struct WordRow: View {
    let word: WordEntry
    let progress: WordProgress?

    private var stage: Int { progress?.stage ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            PlantView(stage: GrowthStage(stage: stage), size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.body.weight(.medium))
                Text(word.meaningSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let progress {
                Text(DateUtil.dueLabel(dueAt: progress.dueAt, now: .now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(word.word)、\(word.meaningSummary)、\(GrowthStage(stage: stage).label)"
        )
    }
}
