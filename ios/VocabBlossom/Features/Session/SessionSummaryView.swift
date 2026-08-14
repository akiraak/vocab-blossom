import SwiftUI

/// 締めの画面。今日育った分を庭の絵と一緒に見せて終わる。
struct SessionSummaryView: View {
    let stats: SessionRunner.Stats
    let onClose: () -> Void

    private let store = WordStore.shared

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<max(1, min(stats.blossomedWordIds.count, 5)), id: \.self) { _ in
                        PlantView(
                            stage: stats.blossomedWordIds.isEmpty ? .sprout : .blossom,
                            size: 44
                        )
                    }
                }
                Text("おつかれさま！")
                    .font(.title2.weight(.bold))
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                row("回答した問題", "\(stats.answered) 問")
                if let accuracy = stats.accuracy {
                    row("正答率", "\(Int((accuracy * 100).rounded())) %")
                }
                row("新しく覚えた語", "\(stats.learnedWordIds.count) 語")
                if !stats.knownWordIds.isEmpty {
                    row("もう知ってる", "\(stats.knownWordIds.count) 語")
                }
                row("開花した語", "\(stats.blossomedWordIds.count) 語")
            }
            .cardStyle()

            if !stats.blossomedWordIds.isEmpty {
                blossomedList
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Text("庭にもどる")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var headline: String {
        if !stats.blossomedWordIds.isEmpty {
            return "\(stats.blossomedWordIds.count) 語が開花しました 🌸"
        }
        if stats.answered == 0 {
            return "今日は出題がありませんでした"
        }
        return "庭がまた少し育ちました"
    }

    private var blossomedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("開花した単語")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(stats.blossomedWordIds.prefix(5), id: \.self) { wordId in
                if let word = store.word(id: wordId) {
                    HStack(spacing: 8) {
                        PlantView(stage: .blossom, size: 20)
                        Text(word.word).font(.subheadline.weight(.medium))
                        Text(word.meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SessionSummaryView(
        stats: SessionRunner.Stats(
            answered: 18, correct: 15,
            learnedWordIds: ["a1-0001", "a1-0002"],
            blossomedWordIds: ["a1-0003"]
        ),
        onClose: {}
    )
    .padding()
}
