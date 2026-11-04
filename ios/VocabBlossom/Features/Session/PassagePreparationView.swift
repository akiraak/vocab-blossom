import SwiftUI

/// 穴埋めを始める前に、文章を作っている間の画面。
///
/// AI が数十秒かかるので、きらめくアイコンと脈打つ輪で「いま作っている」ことを見せ、
/// 語ごとのチップにチェックが付いていくことで進み具合が分かるようにする。
/// 「視差効果を減らす」がオンなら動かさない。
struct PassagePreparationView: View {
    let preparation: PassagePreparation
    let onRetry: () -> Void
    /// 例文のまま始める（作れなかったとき）
    let onStartWithExamples: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            hero
            titles
            if case .failed(let message) = preparation.phase {
                failure(message)
            } else {
                progress
            }
            chips
            Spacer(minLength: 0)
        }
        .padding(16)
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: preparation.items)
        .animation(.default, value: preparation.phase)
    }

    // MARK: - 部品

    private var isFinished: Bool {
        if case .finished = preparation.phase { return true }
        return false
    }

    private var isAnimating: Bool { !reduceMotion && preparation.phase == .working }

    private var isFailed: Bool {
        if case .failed = preparation.phase { return true }
        return false
    }

    private var hero: some View {
        TimelineView(.animation(paused: reduceMotion || preparation.phase != .working)) { context in
            let phase = Self.pulse(at: context.date)
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 132, height: 132)
                    .scaleEffect(0.86 + 0.14 * phase)
                Circle()
                    .stroke(Theme.accent.opacity(0.35 * (1 - phase)), lineWidth: 3)
                    .frame(width: 132, height: 132)
                    .scaleEffect(0.9 + 0.35 * phase)
                Image(systemName: heroSymbol)
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(isFailed ? Theme.incorrect : Theme.accent)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: isAnimating)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    private var heroSymbol: String {
        if isFailed { return "exclamationmark.triangle" }
        if isFinished { return "checkmark.seal.fill" }
        return "sparkles"
    }

    private var titles: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var title: String {
        switch preparation.phase {
        case .working: "穴埋めの問題を作っています"
        case .finished: "問題ができました"
        case .failed: "問題を作れませんでした"
        }
    }

    private var subtitle: String {
        switch preparation.phase {
        case .working:
            "AI が単語ごとに、答えの手がかりになる文章を 3 つずつ書いています"
        case .finished(let failedCount) where failedCount > 0:
            "\(failedCount) 語は文章を作れなかったので、例文で出します"
        case .finished:
            "まもなく始まります"
        case .failed:
            "例文のまま始めることもできます"
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            ProgressView(value: preparation.progress)
                .tint(Theme.accent)
            Text("\(preparation.doneCount) / \(preparation.total) 語")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preparation.total) 語中 \(preparation.doneCount) 語できました")
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Label("もう一度作る", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            Button("例文のまま始める", action: onStartWithExamples)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
    }

    private var chips: some View {
        ScrollView {
            FlowLayout(spacing: 8) {
                ForEach(preparation.items) { item in
                    chip(item)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: 220)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func chip(_ item: PassagePreparation.Item) -> some View {
        HStack(spacing: 6) {
            switch item.state {
            case .waiting:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, isActive: isAnimating)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.correct)
                    .transition(.scale)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            Text(item.word)
                .font(.subheadline.weight(.medium))
            if let detail = item.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            item.state == .done ? Theme.correct.opacity(0.12) : Color(.secondarySystemGroupedBackground),
            in: Capsule()
        )
        .opacity(item.state == .waiting ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }

    /// 1.8 秒周期で 0〜1 を行き来する
    private static func pulse(at date: Date) -> Double {
        (sin(date.timeIntervalSinceReferenceDate * .pi / 0.9) + 1) / 2
    }
}

/// チップを横に並べ、入りきらなければ折り返す
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            // 行ごとに中央へ寄せる
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
