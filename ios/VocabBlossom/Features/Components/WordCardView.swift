import SwiftUI

/// 単語・品詞・意味・例文・音声をまとめたカード。
///
/// 提示カード / 回答後カード / 単語詳細で共通に使い、いつも「目 + 耳」のセットで触れられるようにする。
struct WordCardView: View {
    let word: WordEntry
    /// 意味と例文訳を伏せる（提示前に答えを見せたくない場面で使う）
    var hidesMeaning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.word)
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                SpeakButton(word: word)
                Spacer(minLength: 0)
                Text(word.pos.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }

            if !hidesMeaning {
                Text(word.meaning)
                    .font(.title3.weight(.medium))
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(word.example)
                    .font(.callout)
                if !hidesMeaning {
                    Text(word.exampleJa)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 単語 + 例文を読み上げるボタン。
struct SpeakButton: View {
    let word: WordEntry
    var size: Font = .title3

    var body: some View {
        Button {
            SpeechService.shared.speak(word: word.word, example: word.example)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .accessibilityLabel("\(word.word) を読み上げる")
    }
}

#Preview {
    WordCardView(
        word: WordEntry(
            id: "a1-0004", word: "action", pos: .noun, level: .a1, meaning: "行動",
            example: "He is a man of action.", exampleJa: "彼は行動の人です。"
        )
    )
    .cardStyle()
    .padding()
}
