import SwiftUI

/// 4 択クイズ 1 問。回答後は正誤と単語カードをそのまま下に見せる。
struct QuizCardView: View {
    let quiz: Quiz
    let kind: AnswerKind
    let selectedIndex: Int?
    let onSelect: (Int) -> Void
    let onNext: () -> Void

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
        switch kind {
        case .review: "復習"
        case .new: "確認クイズ"
        case .requeue: "もう一度"
        }
    }

    private var kindSymbol: String {
        switch kind {
        case .review: "arrow.clockwise"
        case .new: "sparkles"
        case .requeue: "arrow.uturn.left"
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
                Text(quiz.word.meaning)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
            case .fillBlank:
                Text(quiz.blankedExample ?? quiz.word.example)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("空欄に入る語は？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .listening:
                Button {
                    SpeechService.shared.speak(word: quiz.word.word, example: quiz.word.example)
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

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                isCorrect ? "正解！" : "おしい！",
                systemImage: isCorrect ? "checkmark.seal.fill" : "arrow.uturn.left.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(isCorrect ? Theme.correct : Theme.incorrect)

            WordCardView(word: quiz.word)
        }
        .cardStyle()
        .transition(.opacity)
    }
}
