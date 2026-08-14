import SwiftUI

/// 新規学習の提示カード。この直後に同じ 5 語を 4 択で確認する。
struct PresentationCardView: View {
    let word: WordEntry
    let onKnown: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label("新しい単語", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                WordCardView(word: word)
                    .cardStyle()
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button(action: onNext) {
                    Text("覚えた！")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onKnown) {
                    Text("もう知ってる")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
