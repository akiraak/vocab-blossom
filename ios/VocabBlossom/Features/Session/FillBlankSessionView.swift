import SwiftUI

/// グループの穴埋めモード。文章の無い語があれば先に作り（`PassagePreparationView`）、作り終えたら出題する。
///
/// 作る画面と出題を 1 つのフルスクリーンの中で切り替える（閉じてから開き直すと画面が 2 回動くため）。
/// サーバーの設定が無い・作る語が無いときは、すぐ出題する
struct FillBlankSessionView: View {
    let words: [WordEntry]
    let closeTitle: String

    @Environment(\.passageFetcher) private var fetcher
    @Environment(\.passageCache) private var cache
    @Environment(\.dismiss) private var dismiss

    @State private var preparation: PassagePreparation?
    /// 出題を始めた語（並びはシャッフル済み）。nil の間は作る画面
    @State private var startedWordIds: [String]?

    var body: some View {
        Group {
            if let startedWordIds {
                SessionView(drillWordIds: startedWordIds, quizType: .fillBlank, closeTitle: closeTitle)
                    .transition(.opacity)
            } else {
                NavigationStack {
                    Group {
                        if let preparation {
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
        .animation(.easeInOut(duration: 0.3), value: startedWordIds)
        .task {
            guard preparation == nil, startedWordIds == nil else { return }
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

    private func start() {
        let lookup = cache.lookup
        startedWordIds = words.filter { QuizBuilder.canFillBlank($0, passages: lookup) }.map(\.id).shuffled()
    }
}

extension EnvironmentValues {
    /// 端末にためた穴埋めの文章。画面確認では空のキャッシュに差し替える
    @Entry var passageCache: PassageCache = .shared
}
