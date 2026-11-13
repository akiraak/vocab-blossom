import SwiftUI

/// グループの穴埋めモード。最初に答え方（4 択 / キーボードで入力）を選び、全語の文章を作り直してから
/// （`PassagePreparationView`。同じ文章を出さないよう、文章のある語も毎回作る）、全語の問題を組み立てる。
/// 4 択は選択肢を AI で判定してから出題する（空欄に入るほかの誤答肢も正解にするため）。入力は選択肢が無いのですぐ出題する。
///
/// 選ぶ画面・作る画面・出題を 1 つのフルスクリーンの中で切り替える（閉じてから開き直すと画面が 2 回動くため）。
/// サーバーの設定が無いときは、今ある文章（無ければ例文）ですぐ出題する。作り直せなかった語も同じ。
/// 判定できなかったときは、正解は出題した語だけで出題する。設計は docs/plans/fill-blank-typing.md
struct FillBlankSessionView: View {
    let words: [WordEntry]
    let closeTitle: String
    /// 始めたグループ。回答をグループの記録（`GroupAnswerLog`）に残す
    var groupId: UUID?
    /// 答え方を選ぶ画面を飛ばすときの答え方（画面確認用）
    var initialInput: QuizInput?

    @Environment(\.passageFetcher) private var fetcher
    @Environment(\.fillBlankChecker) private var checker
    @Environment(\.passageCache) private var cache
    @Environment(\.passageHistory) private var history
    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.dismiss) private var dismiss

    /// 選んだ答え方。nil の間は選ぶ画面
    @State private var input: QuizInput?
    @State private var preparation: PassagePreparation?
    /// 組み立てて判定している問題。判定の間だけ入る（「確かめずに始める」で使う）
    @State private var checkingQuizzes: [Quiz]?
    @State private var checkTask: Task<Void, Never>?
    /// 選ぶ画面から始めた、文章を作る処理。閉じたら止める
    @State private var prepareTask: Task<Void, Never>?
    /// 出題を始めた問題（並びはシャッフル済み）。nil の間は作る画面
    @State private var startedQuizzes: [Quiz]?

    var body: some View {
        Group {
            if let startedQuizzes {
                SessionView(
                    drillQuizzes: startedQuizzes,
                    closeTitle: closeTitle,
                    group: groupId.map {
                        GroupAnswerContext(
                            groupId: $0, source: input == .typing ? .fillBlankTyping : .fillBlank
                        )
                    }
                )
                    .transition(.opacity)
            } else {
                NavigationStack {
                    Group {
                        if input == nil {
                            inputPicker
                        } else if checkingQuizzes != nil {
                            checkingView
                        } else if let preparation {
                            PassagePreparationView(
                                preparation: preparation,
                                onRetry: { Task { await prepare() } },
                                onStartWithExamples: start
                            )
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .gardenBackground()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("穴埋めを閉じる")
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: startedQuizzes != nil)
        .onDisappear {
            checkTask?.cancel()
            prepareTask?.cancel()
        }
        .task {
            if input == nil, let initialInput { await choose(initialInput) }
        }
    }

    /// 答え方を決めて、全語の文章を作り直す。サーバーの設定が無ければ、今ある文章ですぐ始める
    private func choose(_ chosen: QuizInput) async {
        guard input == nil else { return }
        input = chosen
        let requests = PassagePreparation.allWords(words)
        guard !requests.isEmpty, fetcher != nil else {
            start()
            return
        }
        preparation = PassagePreparation(requests: requests, refresh: true)
        await prepare()
    }

    private func prepare() async {
        guard let preparation, let fetcher else { return }
        await preparation.run(fetcher: fetcher, cache: cache)
        if case .finished = preparation.phase {
            // 「できました」を一瞬見せてから始める
            try? await Task.sleep(for: .milliseconds(800))
            start()
        }
    }

    /// 全語の問題を組み立て、4 択は選択肢を判定してから出題する
    private func start() {
        guard startedQuizzes == nil, checkingQuizzes == nil, let input else { return }
        let lookup = cache.lookup
        var builder = QuizBuilder(
            store: store, groups: WordGroup.quizGroups(in: context), passages: lookup, passageHistory: history
        )
        let quizzes = words.filter { QuizBuilder.canFillBlank($0, passages: lookup) }
            .shuffled()
            .map { builder.make(for: $0, type: .fillBlank, input: input) }
        guard let checker, !FillBlankCheck.items(for: quizzes).isEmpty else {
            startedQuizzes = quizzes
            return
        }
        checkingQuizzes = quizzes
        checkTask = Task {
            let checked = await FillBlankCheck.run(quizzes, checker: checker)
            guard !Task.isCancelled, startedQuizzes == nil else { return }
            checkingQuizzes = nil
            startedQuizzes = checked
        }
    }

    /// 判定を待たずに始める（正解は出題した語だけ）
    private func skipCheck() {
        guard let quizzes = checkingQuizzes else { return }
        checkTask?.cancel()
        checkingQuizzes = nil
        startedQuizzes = quizzes
    }

    /// 最初の画面: 答え方を選ぶ
    private var inputPicker: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("答え方を選ぶ")
                    .font(.system(size: 22, weight: .light))
                Text("文章は毎回、AI が新しく作ります")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                inputButton(
                    "4 択で選ぶ", detail: "空欄に入る語を 4 つから選ぶ", systemImage: "list.bullet", input: .choice
                )
                inputButton(
                    "キーボードで入力", detail: "空欄に入る語を自分で打つ", systemImage: "keyboard", input: .typing
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inputButton(
        _ title: String, detail: String, systemImage: String, input: QuizInput
    ) -> some View {
        Button {
            prepareTask = Task { await choose(input) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Theme.tintSprout, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("選択肢を確かめています")
                .font(.system(size: 22, weight: .light))
            Text("AI が、ほかにも正解になる選択肢が無いかを見ています")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("確かめずに始める", action: skipCheck)
                .buttonStyle(.capsuleSecondary)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EnvironmentValues {
    /// 端末にためた穴埋めの文章。画面確認では空のキャッシュに差し替える
    @Entry var passageCache: PassageCache = .shared
    /// 穴埋めで最後に出した文章。次は前回の次の文章から出す
    @Entry var passageHistory: PassageHistory = .shared
}
