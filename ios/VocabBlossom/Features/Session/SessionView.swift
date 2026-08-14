import SwiftData
import SwiftUI

/// 学習/復習セッションのフルスクリーン。
///
/// 何を勉強するか・どの形式で解くかはアプリが決めるので、ユーザーは
/// 「ボタンを押す → クイズに答える」だけで進む。
struct SessionView: View {
    let plan: SessionPlan

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var runner: SessionRunner?

    var body: some View {
        NavigationStack {
            Group {
                if let runner {
                    content(runner)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .gardenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        SpeechService.shared.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("セッションを閉じる")
                }
            }
        }
        .task {
            if runner == nil {
                runner = SessionRunner(plan: plan, engine: LearningEngine(context: context))
            }
        }
        .onDisappear { SpeechService.shared.stop() }
    }

    @ViewBuilder
    private func content(_ runner: SessionRunner) -> some View {
        VStack(spacing: 0) {
            if !runner.isFinished {
                header(runner)
            }
            step(runner)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: runner.step.id) { speakIfNeeded(runner.step) }
        .onChange(of: runner.selectedIndex) { _, newValue in
            guard newValue != nil, case .quiz(let quiz, _) = runner.step else { return }
            // 回答後は正誤にかかわらず単語と例文を読み上げて定着を促す
            speak(word: quiz.word.word, example: quiz.word.example)
        }
    }

    @ViewBuilder
    private func step(_ runner: SessionRunner) -> some View {
        switch runner.step {
        case .present(let word):
            PresentationCardView(
                word: word,
                onKnown: { runner.markKnown() },
                onNext: { runner.next() }
            )
        case .quiz(let quiz, let kind):
            QuizCardView(
                quiz: quiz,
                kind: kind,
                selectedIndex: runner.selectedIndex,
                onSelect: { runner.answer(choiceIndex: $0) },
                onNext: { runner.next() }
            )
        case .summary:
            SessionSummaryView(stats: runner.stats) { dismiss() }
        }
    }

    private func header(_ runner: SessionRunner) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: runner.progress)
                .tint(Theme.accent)
            Text("残り \(runner.remainingCount) 問")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func speakIfNeeded(_ step: SessionRunner.Step) {
        switch step {
        case .present(let word):
            speak(word: word.word, example: word.example)
        case .quiz(let quiz, _):
            guard let speech = quiz.speechOnPrompt else { return }
            speak(word: speech.word, example: speech.example)
        case .summary:
            SpeechService.shared.stop()
        }
    }

    private func speak(word: String, example: String) {
        guard settings.soundEnabled else { return }
        if example.isEmpty {
            SpeechService.shared.speak(word: word)
        } else {
            SpeechService.shared.speak(word: word, example: example)
        }
    }
}
