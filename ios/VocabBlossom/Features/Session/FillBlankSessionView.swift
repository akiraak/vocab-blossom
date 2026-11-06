import SwiftUI

/// グループの穴埋めモード。文章の無い語があれば先に作り（`PassagePreparationView`）、作り終えたら
/// 全語の問題を組み立てて、選択肢を AI で判定してから出題する（空欄に入るほかの誤答肢も正解にするため）。
///
/// 作る画面と出題を 1 つのフルスクリーンの中で切り替える（閉じてから開き直すと画面が 2 回動くため）。
/// サーバーの設定が無い・作る語が無いときは、すぐ出題する。判定できなかったときは、正解は出題した語だけで出題する
struct FillBlankSessionView: View {
    let words: [WordEntry]
    let closeTitle: String
    /// 始めたグループ。回答をグループの記録（`GroupAnswerLog`）に残す
    var groupId: UUID?

    @Environment(\.passageFetcher) private var fetcher
    @Environment(\.fillBlankChecker) private var checker
    @Environment(\.passageCache) private var cache
    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var preparation: PassagePreparation?
    /// 組み立てて判定している問題。判定の間だけ入る（「確かめずに始める」で使う）
    @State private var checkingQuizzes: [Quiz]?
    @State private var checkTask: Task<Void, Never>?
    /// 出題を始めた問題（並びはシャッフル済み）。nil の間は作る画面
    @State private var startedQuizzes: [Quiz]?

    var body: some View {
        Group {
            if let startedQuizzes {
                SessionView(
                    drillQuizzes: startedQuizzes,
                    closeTitle: closeTitle,
                    group: groupId.map { GroupAnswerContext(groupId: $0, source: .fillBlank) }
                )
                    .transition(.opacity)
            } else {
                NavigationStack {
                    Group {
                        if checkingQuizzes != nil {
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
        .onDisappear { checkTask?.cancel() }
        .task {
            guard preparation == nil, startedQuizzes == nil else { return }
            let missing = PassagePreparation.missingWords(words, cache: cache)
            guard !missing.isEmpty, fetcher != nil else {
                start()
                return
            }
            preparation = PassagePreparation(requests: missing)
            await prepare()
        }
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

    /// 全語の問題を組み立て、選択肢を判定してから出題する
    private func start() {
        guard startedQuizzes == nil, checkingQuizzes == nil else { return }
        let lookup = cache.lookup
        var builder = QuizBuilder(store: store, groups: WordGroup.quizGroups(in: context), passages: lookup)
        let quizzes = words.filter { QuizBuilder.canFillBlank($0, passages: lookup) }
            .shuffled()
            .map { builder.make(for: $0, type: .fillBlank) }
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

    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("選択肢を確かめています")
                .font(.title3.weight(.bold))
            Text("AI が、ほかにも正解になる選択肢が無いかを見ています")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("確かめずに始める", action: skipCheck)
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EnvironmentValues {
    /// 端末にためた穴埋めの文章。画面確認では空のキャッシュに差し替える
    @Entry var passageCache: PassageCache = .shared
}
