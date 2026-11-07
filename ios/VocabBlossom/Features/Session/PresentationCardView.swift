import SwiftUI

/// 新規学習の提示カード。この直後に同じ 5 語を 4 択で確認する。
struct PresentationCardView: View {
    let word: WordEntry
    let onKnown: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label("新しい単語", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.tintBlossom, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                WordCardView(word: word)
                    .cardStyle(Theme.tintBud)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button("覚えた！", action: onNext)
                    .buttonStyle(.capsule)
                Button("もう知ってる", action: onKnown)
                    .buttonStyle(.capsuleSecondary)
            }
        }
    }
}
