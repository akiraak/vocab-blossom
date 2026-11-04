import SwiftUI

/// AI チェックの待ち時間に出す行。
///
/// 小さな `ProgressView` だけだと処理中だと気づきにくいので、きらめくアイコンと、
/// 候補が入る場所の骨組みを明滅させて「いま調べている」ことが分かるようにする。
/// 「視差効果を減らす」がオンなら動かさない。
struct AssistLoadingView: View {
    /// AI に送った文字列
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: !reduceMotion)
                VStack(alignment: .leading, spacing: 2) {
                    Text("「\(text)」を AI で調べています…")
                        .font(.subheadline.weight(.semibold))
                    Text("綴り・意味・例文を確かめています")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // List の行の中でも止まらないよう、明滅は TimelineView で時刻から計算する
            TimelineView(.animation(paused: reduceMotion)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    placeholderBar(width: 110)
                    placeholderBar(width: 230)
                    placeholderBar(width: 170)
                }
                .opacity(Self.pulseOpacity(at: context.date))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("「\(text)」を AI で調べています")
    }

    private func placeholderBar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Theme.accent.opacity(0.32))
            .frame(maxWidth: width, minHeight: 10, maxHeight: 10)
    }

    /// 1.6 秒周期で 0.25〜1.0 を行き来する
    private static func pulseOpacity(at date: Date) -> Double {
        let phase = (sin(date.timeIntervalSinceReferenceDate * .pi / 0.8) + 1) / 2
        return 0.25 + 0.75 * phase
    }
}
