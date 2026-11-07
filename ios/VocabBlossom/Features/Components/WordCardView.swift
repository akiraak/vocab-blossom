import SwiftUI

/// 単語・品詞・意味・例文・音声をまとめたカード。
///
/// 提示カード / 回答後カード / 単語詳細で共通に使い、いつも「目 + 耳」のセットで触れられるようにする。
/// 意味が複数ある語（自作語）は、品詞ごとに意味と例文を並べる
struct WordCardView: View {
    let word: WordEntry
    /// 意味と例文訳を伏せる（提示前に答えを見せたくない場面で使う）
    var hidesMeaning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.word)
                    .font(.system(size: 30, weight: .light))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                SpeakButton(word: word)
                Spacer(minLength: 0)
                if word.extraSenses.isEmpty {
                    posCapsule(word.pos)
                }
            }

            if word.extraSenses.isEmpty {
                if !hidesMeaning {
                    Text(word.meaning)
                        .font(.title3.weight(.medium))
                }
                exampleBlock(word.primarySense, withDivider: true)
            } else {
                ForEach(Array(word.senses.enumerated()), id: \.offset) { index, sense in
                    if index > 0 {
                        Divider()
                    }
                    senseBlock(sense)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func posCapsule(_ pos: PartOfSpeech) -> some View {
        Text(pos.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.background, in: Capsule())
    }

    /// 意味が複数あるときの 1 つ分（品詞・意味・例文）
    private func senseBlock(_ sense: WordSense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                posCapsule(sense.pos)
                if !hidesMeaning {
                    Text(sense.meaning)
                        .font(.headline)
                }
            }
            exampleBlock(sense, withDivider: false)
        }
        .accessibilityElement(children: .combine)
    }

    /// 例文と訳。自作語は例文が任意なので、無ければ区切り線ごと出さない
    @ViewBuilder
    private func exampleBlock(_ sense: WordSense, withDivider: Bool) -> some View {
        if !sense.example.isEmpty {
            if withDivider {
                Divider()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sense.example)
                    .font(.callout)
                if !hidesMeaning, !sense.exampleJa.isEmpty {
                    Text(sense.exampleJa)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 単語 + 例文を読み上げるボタン（Gemini の声。設定の「自動で読み上げる」に関係なく鳴らす）。
struct SpeakButton: View {
    let word: WordEntry
    var size: Font = .title3

    var body: some View {
        Button {
            GeminiReadAloudSpeaker.quiz.speak(
                ReadAloudScript.learningLines(word: word.word, example: word.example)
            )
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .accessibilityLabel("\(word.word) を読み上げる")
    }
}

#Preview("意味が複数") {
    WordCardView(
        word: WordEntry(
            id: "custom-commute", word: "commute", pos: .verb, level: nil, meaning: "通勤する、通学する",
            example: "I commute to school by bus.", exampleJa: "私はバスで通学します。",
            extraSenses: [
                WordSense(
                    pos: .noun, meaning: "通勤、通学",
                    example: "My commute takes an hour.", exampleJa: "私の通勤には 1 時間かかります。"
                ),
            ]
        )
    )
    .cardStyle()
    .padding()
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
