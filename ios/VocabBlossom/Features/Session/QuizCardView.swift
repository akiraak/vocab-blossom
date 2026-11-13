import SwiftUI

/// クイズ 1 問。4 択か、穴埋めをキーボードで入力（`quiz.input == .typing`）。回答後は正誤と単語カードをそのまま下に見せる。
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
    /// 入力の問題で回答済みなら打った綴り（「わからない」は空）。未回答は nil
    var typedAnswer: String?
    /// 入力の問題に答える（「わからない」は空で呼ぶ）
    var onSubmitTyped: (String) -> Void = { _ in }

    /// 入力の問題で打っている途中の綴り
    @State private var draft = ""

    private var isTyping: Bool { quiz.input == .typing }
    private var isAnswered: Bool { selectedIndex != nil || typedAnswer != nil }
    private var isCorrect: Bool {
        if let typedAnswer { return quiz.isCorrect(typed: typedAnswer) }
        return selectedIndex.map { quiz.isCorrect(choiceIndex: $0) } ?? false
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 正解の色にする選択肢（出題した語と、ほかにも正解の語）
    private func isCorrectChoice(_ index: Int) -> Bool { quiz.isCorrect(choiceIndex: index) }

    /// ほかにも正解の語（出題した語ではない）
    private func isAlsoCorrect(_ index: Int) -> Bool { index != quiz.answerIndex && isCorrectChoice(index) }

    var body: some View {
        VStack(spacing: 16) {
            headerLabels
            ScrollView {
                VStack(spacing: 16) {
                    prompt
                    if !isTyping {
                        choices
                    } else if let typedAnswer {
                        typedResult(typedAnswer)
                    }
                    if isAnswered {
                        feedback
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if isAnswered {
                Button("次へ", action: onNext)
                    .buttonStyle(.capsule)
            } else if isTyping {
                // 入力欄はスクロールの外に置く（キーボードが出ても、長い文章に押し出されないように）
                typingEntry
            }
        }
        .onChange(of: quiz.id) { draft = "" }
    }

    // MARK: - 入力の問題

    private func submitDraft() {
        guard !trimmedDraft.isEmpty else { return }
        onSubmitTyped(trimmedDraft)
    }

    /// 入力欄と「わからない」「答える」
    private var typingEntry: some View {
        VStack(spacing: 10) {
            TypingAnswerField(text: $draft, onSubmit: submitDraft)
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 1.5)
                )
            HStack(spacing: 10) {
                Button("わからない") { onSubmitTyped("") }
                    .buttonStyle(.capsuleSecondary)
                Button("答える", action: submitDraft)
                    .buttonStyle(.capsule)
                    .disabled(trimmedDraft.isEmpty)
            }
        }
    }

    /// 答えたあと: 打った綴りと、間違えたときは正解の綴り
    private func typedResult(_ typed: String) -> some View {
        VStack(spacing: 10) {
            typedRow(label: "あなたの答え", text: typed.isEmpty ? "わからない" : typed, correct: isCorrect)
            if !isCorrect, let answer = quiz.typedAnswer {
                typedRow(label: "正解", text: answer, correct: true)
            }
            if quiz.isHeadwordInOtherForm(typed: typed), let answer = quiz.typedAnswer {
                Label("この文では「\(answer)」の形で入ります", systemImage: "lightbulb")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func typedRow(label: String, text: String, correct: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.body.weight(.medium))
            }
            Spacer(minLength: 8)
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? Theme.correct : Theme.incorrect)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            correct ? Theme.tintBlossom : Theme.incorrect.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(correct ? Theme.correct : Theme.incorrect, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }

    private var headerLabels: some View {
        HStack(spacing: 10) {
            Text(quiz.type.label)
                .sectionLabel()
            Label(kindLabel, systemImage: kindSymbol)
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.tintBlossom, in: Capsule())
            Spacer()
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
                    .font(.system(size: 44, weight: .light))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                SpeakButton(word: quiz.word, size: .title2)
            case .jaToEn:
                Text(quiz.sense.meaning)
                    .font(.system(size: 28, weight: .regular))
                    .multilineTextAlignment(.center)
            case .fillBlank:
                Text(quiz.blankedExample ?? quiz.sense.example)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(isTyping ? "空欄に入る語を入力" : "空欄に入る語は？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .listening:
                Button {
                    GeminiReadAloudSpeaker.quiz.speak(
                        ReadAloudScript.learningLines(word: quiz.word.word, example: quiz.sense.example)
                    )
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
        .frame(maxWidth: .infinity, minHeight: 170)
        .cardStyle(Theme.tintBud)
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
                        if isAnswered, isAlsoCorrect(index) {
                            Text("これも正解")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.correct)
                        }
                        if isAnswered, isCorrectChoice(index) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.correct)
                        } else if isAnswered, index == selectedIndex {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.incorrect)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(background(for: index), in: RoundedRectangle(
                        cornerRadius: 18, style: .continuous
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(border(for: index), lineWidth: isAnswered ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAnswered)
                .accessibilityHint(isAnswered ? "" : "選択して回答します")
            }
        }
    }

    /// 答える前は白地に細い枠線。答えたら正解は色面 ＋ セージの枠、選んだ誤りは赤みの色面 ＋ 枠
    private func background(for index: Int) -> Color {
        guard isAnswered else { return Theme.background }
        if isCorrectChoice(index) { return Theme.tintBlossom }
        if index == selectedIndex { return Theme.incorrect.opacity(0.1) }
        return Theme.background
    }

    private func border(for index: Int) -> Color {
        guard isAnswered else { return Theme.hairline }
        if isCorrectChoice(index) { return Theme.correct }
        if index == selectedIndex { return Theme.incorrect }
        return Theme.hairline
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
        .background(Theme.tintSprout, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// ほかにも正解の語があるときの説明。ほかの正解を選んだときは、出題した語が何だったかも見せる
    private var alsoCorrectNote: some View {
        let others = quiz.alsoCorrectChoices.map { "「\($0.word)」" }.joined(separator: "・")
        let pickedAlso = selectedIndex.map(isAlsoCorrect) ?? false
        let text = pickedAlso
            ? "この文の答えは「\(quiz.word.word)」。\(others)も入ります"
            : "\(others)も入ります"
        return Label(text, systemImage: "lightbulb")
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
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

            if !quiz.alsoCorrectChoices.isEmpty {
                alsoCorrectNote
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
