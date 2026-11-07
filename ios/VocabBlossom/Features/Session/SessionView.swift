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
        /// グループのドリル（進捗を動かさない）。`quizType` を渡すとその形式で固定する
        case drill(wordIds: [String], quizType: QuizType?)
        /// 組み立て済みの問題のドリル（グループの穴埋めモード。選択肢を AI で判定してある）
        case prepared([Quiz])
    }

    let source: Source
    /// 締め画面の閉じるボタンの文言
    var closeTitle = "ホームにもどる"
    /// グループから始めたときの入口。回答をグループの記録（`GroupAnswerLog`）に残す
    var group: GroupAnswerContext?

    init(plan: SessionPlan, closeTitle: String = "ホームにもどる", group: GroupAnswerContext? = nil) {
        source = .plan(plan)
        self.closeTitle = closeTitle
        self.group = group
    }

    init(
        drillWordIds: [String],
        quizType: QuizType? = nil,
        closeTitle: String,
        group: GroupAnswerContext? = nil
    ) {
        source = .drill(wordIds: drillWordIds, quizType: quizType)
        self.closeTitle = closeTitle
        self.group = group
    }

    init(drillQuizzes: [Quiz], closeTitle: String, group: GroupAnswerContext? = nil) {
        source = .prepared(drillQuizzes)
        self.closeTitle = closeTitle
        self.group = group
    }

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.passageCache) private var passageCache
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
                        stopSpeaking()
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
                // 自作語の誤答肢を同じグループの語から、つなぎ言葉の誤答肢を働きの違うグループから選ぶため、グループを渡す
                let groups = WordGroup.quizGroups(in: context)
                // 穴埋めは、端末にためた文章があれば例文より優先して使う
                let passages = passageCache.lookup
                switch source {
                case .plan(let plan):
                    runner = SessionRunner(
                        plan: plan, engine: engine, store: store, groups: groups, passages: passages,
                        group: group
                    )
                case .drill(let wordIds, let quizType):
                    runner = SessionRunner(
                        drillWordIds: wordIds, quizType: quizType,
                        engine: engine, store: store, groups: groups, passages: passages,
                        group: group
                    )
                case .prepared(let quizzes):
                    runner = SessionRunner(drillQuizzes: quizzes, engine: engine, store: store, group: group)
                }
            }
        }
        .onDisappear { stopSpeaking() }
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
        .task(id: runner.step.id) { speakIfNeeded(runner) }
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
                onNext: { runner.next() },
                onReplay: quiz.type == .fillBlank ? { speakFillBlankAnswer(quiz) } : nil
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
                .scaleEffect(x: 1, y: 0.6, anchor: .center)
            Text("残り \(runner.remainingCount) 問")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 回答直後のフィードバック。正誤の効果音を鳴らし、少し置いてから
    /// 単語と例文を読み上げて定着を促す（正誤にかかわらず読む）。穴埋めは単語と出題した文章を読む。
    /// 読み上げはすべて Gemini の声（`GeminiReadAloudSpeaker.quiz`。取れなければ内蔵の声）。
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
        guard settings.soundEnabled else { return }
        GeminiReadAloudSpeaker.quiz.speak(answerLines(for: quiz))
    }

    /// このあと出す語のうち、音声を先に取っておく数
    private static let prefetchWordCount = 5

    private func speakIfNeeded(_ runner: SessionRunner) {
        let speaker = GeminiReadAloudSpeaker.quiz
        // 前のカードの読み上げが残っていれば止める
        speaker.stop()
        var prefetch: [[ReadAloudLine]] = []
        switch runner.step {
        case .present(let word):
            prefetch.append(speak(word: word.word, example: word.example))
        case .quiz(let quiz, _):
            if let speech = quiz.speechOnPrompt {
                prefetch.append(speak(word: speech.word, example: speech.example))
            }
            // 考えている間に、答えたあとに読む文の音声を取っておく（答えたらすぐ鳴らすため）
            prefetch.append(answerLines(for: quiz))
        case .summary:
            speaker.finish()
            return
        }
        // カードが出たらすぐ鳴るよう、このあと出す数語の音声も取っておく
        prefetch += runner.upcomingWords(limit: Self.prefetchWordCount)
            .map(ReadAloudScript.learningPrefetchLines)
        if settings.soundEnabled {
            speaker.prefetch(prefetch)
        }
    }

    /// 回答後に読む文。穴埋めは単語 → 出題した文章（文章で出したときはその全文、例文で出したときは例文）。
    /// ほかの形式は単語 → 出題した意味の例文（意味が複数ある語は、出題した意味の例文を読む）
    private func answerLines(for quiz: Quiz) -> [ReadAloudLine] {
        quiz.type == .fillBlank
            ? ReadAloudScript.fillBlankAnswerLines(for: quiz)
            : ReadAloudScript.learningLines(word: quiz.word.word, example: quiz.sense.example)
    }

    private func speakFillBlankAnswer(_ quiz: Quiz) {
        GeminiReadAloudSpeaker.quiz.speak(answerLines(for: quiz))
    }

    /// 読み上げをすべて止め、少し待ってから音声セッションを無効化する（閉じるとき）
    private func stopSpeaking() {
        GeminiReadAloudSpeaker.quiz.finish()
    }

    /// 自動の読み上げ。設定でオフなら読まない。読む（読む予定だった）文を返す（先読みに使う）
    @discardableResult
    private func speak(word: String, example: String) -> [ReadAloudLine] {
        let lines = ReadAloudScript.learningLines(word: word, example: example)
        if settings.soundEnabled {
            GeminiReadAloudSpeaker.quiz.speak(lines)
        }
        return lines
    }
}
