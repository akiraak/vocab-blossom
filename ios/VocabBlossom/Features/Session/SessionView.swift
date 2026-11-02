import SwiftData
import SwiftUI

/// 学習/復習セッションのフルスクリーン。
///
/// 何を勉強するか・どの形式で解くかはアプリが決めるので、ユーザーは
/// 「ボタンを押す → クイズに答える」だけで進む。
struct SessionView: View {
    enum Source {
        /// いつもの学習（毎日 / グループ）
        case plan(SessionPlan)
        /// グループのドリル（進捗を動かさない）
        case drill(wordIds: [String])
    }

    let source: Source
    /// 締め画面の閉じるボタンの文言
    var closeTitle = "庭にもどる"

    init(plan: SessionPlan, closeTitle: String = "庭にもどる") {
        source = .plan(plan)
        self.closeTitle = closeTitle
    }

    init(drillWordIds: [String], closeTitle: String) {
        source = .drill(wordIds: drillWordIds)
        self.closeTitle = closeTitle
    }

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
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
                let engine = LearningEngine(context: context)
                switch source {
                case .plan(let plan):
                    runner = SessionRunner(plan: plan, engine: engine, store: store)
                case .drill(let wordIds):
                    runner = SessionRunner(drillWordIds: wordIds, engine: engine, store: store)
                }
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
        .task(id: runner.selectedIndex) { await feedbackAfterAnswer(runner) }
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
                isDrill: runner.mode == .drill,
                selectedIndex: runner.selectedIndex,
                onSelect: { runner.answer(choiceIndex: $0) },
                onNext: { runner.next() }
            )
        case .summary:
            SessionSummaryView(
                stats: runner.stats,
                mode: runner.mode,
                closeTitle: closeTitle
            ) { dismiss() }
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

    /// 回答直後のフィードバック。正誤の効果音を鳴らし、少し置いてから
    /// 単語と例文を読み上げて定着を促す（正誤にかかわらず読む）。
    /// 読み上げ前に「次へ」で進んだら読み上げは取りやめる（次のカードと衝突させない）
    private func feedbackAfterAnswer(_ runner: SessionRunner) async {
        guard let correct = runner.lastAnswerWasCorrect,
              case .quiz(let quiz, _) = runner.step else { return }
        if settings.effectSoundEnabled {
            SoundEffectService.shared.play(correct ? .correct : .incorrect)
            // 効果音と読み上げが重ならないよう少し待つ
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }
        speak(word: quiz.word.word, example: quiz.word.example)
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
