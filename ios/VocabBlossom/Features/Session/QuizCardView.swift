import SwiftUI

/// 4 択クイズ 1 問。回答後は正誤と単語カードをそのまま下に見せる。
struct QuizCardView: View {
    let quiz: Quiz
    let kind: AnswerKind
    /// ドリル（進捗を動かさない練習）なら見出しを「ドリル」にする
    var isDrill = false
    let selectedIndex: Int?
    let onSelect: (Int) -> Void
    let onNext: () -> Void
    /// 答えたあとの「もう一度聞く」（穴埋めだけ。単語 → 出題した文章を読む）。nil ならボタンを出さない
    var onReplay: (() -> Void)?

    private var isAnswered: Bool { selectedIndex != nil }
    private var isCorrect: Bool { selectedIndex == quiz.answerIndex }

    var body: some View {
        VStack(spacing: 16) {
            headerLabels
            ScrollView {
                VStack(spacing: 16) {
                    prompt
                    choices
                    if isAnswered {
                        feedback
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if isAnswered {
                Button(action: onNext) {
                    Text("次へ")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var headerLabels: some View {
        HStack {
            Label(kindLabel, systemImage: kindSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Spacer()
            Text(quiz.type.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
    }

    private var kindLabel: String {
        if isDrill, kind != .requeue { return "ドリル" }
        switch kind {
        case .review: return "復習"
        case .new: return "確認クイズ"
        case .requeue: return "もう一度"
        }
    }

    private var kindSymbol: String {
        if isDrill, kind != .requeue { return "pencil.and.list.clipboard" }
        switch kind {
        case .review: return "arrow.clockwise"
        case .new: return "sparkles"
        case .requeue: return "arrow.uturn.left"
        }
    }

    @ViewBuilder
    private var prompt: some View {
        VStack(spacing: 12) {
            switch quiz.type {
            case .enToJa:
                Text(quiz.word.word)
                    .font(.system(.largeTitle, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                SpeakButton(word: quiz.word, size: .title2)
            case .jaToEn:
                Text(quiz.sense.meaning)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
            case .fillBlank:
                Text(quiz.blankedExample ?? quiz.sense.example)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("空欄に入る語は？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .listening:
                Button {
                    SpeechService.shared.speak(word: quiz.word.word, example: quiz.sense.example)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(.largeTitle))
                        Text("もう一度聞く")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("音声をもう一度聞く")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .cardStyle()
    }

    private var choices: some View {
        VStack(spacing: 10) {
            ForEach(Array(quiz.choices.enumerated()), id: \.element.id) { index, choice in
                Button {
                    onSelect(index)
                } label: {
                    HStack {
                        Text(quiz.choiceText(choice))
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if isAnswered, index == quiz.answerIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.correct)
                        } else if isAnswered, index == selectedIndex {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.incorrect)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: index), in: RoundedRectangle(
                        cornerRadius: 12, style: .continuous
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(border(for: index), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAnswered)
                .accessibilityHint(isAnswered ? "" : "選択して回答します")
            }
        }
    }

    private func background(for index: Int) -> Color {
        guard isAnswered else { return Color(.secondarySystemGroupedBackground) }
        if index == quiz.answerIndex { return Theme.correct.opacity(0.15) }
        if index == selectedIndex { return Theme.incorrect.opacity(0.15) }
        return Color(.secondarySystemGroupedBackground).opacity(0.6)
    }

    private func border(for index: Int) -> Color {
        guard isAnswered else { return .clear }
        if index == quiz.answerIndex { return Theme.correct }
        if index == selectedIndex { return Theme.incorrect }
        return .clear
    }

    /// 穴埋めに使った文章の全文と和訳
    private func passageView(_ passage: Passage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(passage.text)
                .font(.subheadline)
            Text(passage.ja)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    isCorrect ? "正解！" : "おしい！",
                    systemImage: isCorrect ? "checkmark.seal.fill" : "arrow.uturn.left.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(isCorrect ? Theme.correct : Theme.incorrect)
                Spacer(minLength: 8)
                if let onReplay {
                    Button(action: onReplay) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("単語と問題の文章をもう一度聞く")
                }
            }

            if let passage = quiz.passage {
                passageView(passage)
            }

            WordCardView(word: quiz.word)
        }
        .cardStyle()
        .transition(.opacity)
    }
}
