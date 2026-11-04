import SwiftData
import SwiftUI

/// グループの中身と、グループ単位の学習（SRS 共有）/ ドリル（進捗を動かさない）の入口。
struct GroupDetailView: View {
    let group: WordGroup

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(AppSettings.self) private var settings
    @Query private var progresses: [WordProgress]

    @State private var session: GroupSession?
    @State private var isPickingWords = false
    @State private var isRenaming = false
    @State private var renameText = ""
    /// 「単語を選んで外す」の選択モード
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    #if DEBUG
    /// 画面確認用に最初から開く単語詳細
    @State private var debugDetailWord: WordEntry?
    #endif

    /// フルスクリーンで開くセッション。押した瞬間の内容で固定する
    enum GroupSession: Identifiable {
        case learn(SessionPlan)
        case drill([String])
        /// 形式を穴埋めに固定したドリル。文章の無い語は始める前に作る
        case fillBlank([WordEntry])

        var id: String {
            switch self {
            case .learn: "learn"
            case .drill: "drill"
            case .fillBlank: "fill-blank"
            }
        }
    }

    private var words: [WordEntry] { store.words(ids: group.wordIds) }

    private var progressByWordId: [String: WordProgress] {
        Dictionary(progresses.map { ($0.wordId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let words = words
        let progressByWordId = progressByWordId
        let plan = GroupStudy.plan(
            GroupStudy.Input(
                now: .now,
                words: words,
                progress: progresses.map(\.snapshot),
                newWordsLimit: settings.newWordsPerDay,
                reviewLimit: settings.reviewLimitPerDay
            )
        )
        let summary = GroupStudy.summary(
            wordIds: words.map(\.id),
            progressByWordId: progressByWordId.mapValues(\.snapshot),
            now: .now
        )

        List(selection: $selection) {
            if !isSelecting {
                Section {
                    studyCard(plan: plan, summary: summary, words: words)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if words.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(words) { word in
                        NavigationLink {
                            WordDetailView(word: word)
                        } label: {
                            WordRow(word: word, progress: progressByWordId[word.id])
                        }
                        .swipeActions {
                            Button("外す", role: .destructive) {
                                remove([word.id])
                            }
                        }
                        .contextMenu {
                            Button("グループから外す", systemImage: "minus.circle", role: .destructive) {
                                remove([word.id])
                            }
                        }
                    }
                } header: {
                    if isSelecting {
                        Text("外す単語を選んでください（\(words.count) 語中 \(selection.count) 語）")
                    } else {
                        Text("\(words.count) 語")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .gardenBackground()
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        // 選択モードの「外す」などは下のツールバーに出すので、タブバーは隠す（重なって押せなくなる）
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if isSelecting {
                selectionToolbar(words: words)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu(isEmpty: words.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPickingWords = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("単語を追加")
                }
            }
        }
        .sheet(isPresented: $isPickingWords) {
            WordPickerView(group: group)
        }
        .alert("名前を変更", isPresented: $isRenaming) {
            TextField("グループ名", text: $renameText)
            Button("変更") { GroupEditor(context: context).rename(group, to: renameText) }
            Button("キャンセル", role: .cancel) {}
        }
        .fullScreenCover(item: $session) { session in
            switch session {
            case .learn(let plan):
                SessionView(plan: plan, closeTitle: "グループにもどる")
            case .drill(let wordIds):
                SessionView(drillWordIds: wordIds, closeTitle: "グループにもどる")
            case .fillBlank(let words):
                FillBlankSessionView(words: words, closeTitle: "グループにもどる")
                    #if DEBUG
                    .debugPassagePreparation()
                    #endif
            }
        }
        #if DEBUG
        .navigationDestination(item: $debugDetailWord) { word in
            WordDetailView(word: word)
        }
        .onAppear {
            switch DebugSeed.variant {
            case .groupLearn: session = .learn(plan)
            case .groupDrill: session = .drill(words.map(\.id))
            case .groupFillBlank, .fillBlankPreparing: session = .fillBlank(words)
            case .drillSenses: session = .drill(words.filter { !$0.extraSenses.isEmpty }.map(\.id))
            case .wordPicker, .wordEditor, .wordEditorLoading, .wordAssistResult, .wordEditorSenses:
                isPickingWords = true
            case .wordDetailSenses:
                debugDetailWord = words.first { !$0.extraSenses.isEmpty }
            case .groupSelect:
                isSelecting = true
                selection = Set(words.prefix(2).map(\.id))
            default: break
            }
        }
        #endif
    }

    private func moreMenu(isEmpty: Bool) -> some View {
        Menu {
            Button {
                renameText = group.name
                isRenaming = true
            } label: {
                Label("名前を変更", systemImage: "pencil")
            }
            Button {
                selection = []
                isSelecting = true
            } label: {
                Label("単語を選んで外す", systemImage: "checklist")
            }
            .disabled(isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("その他")
    }

    // MARK: - 単語を外す

    @ToolbarContentBuilder
    private func selectionToolbar(words: [WordEntry]) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("完了") { endSelecting() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            let allSelected = !words.isEmpty && selection.count == words.count
            Button(allSelected ? "すべて解除" : "すべて選択") {
                selection = allSelected ? [] : Set(words.map(\.id))
            }
            Spacer()
            Button(selection.isEmpty ? "外す" : "外す（\(selection.count)）", role: .destructive) {
                // 一覧の並びで外す（選んだ順は関係ない）
                remove(words.map(\.id).filter(selection.contains))
                endSelecting()
            }
            .disabled(selection.isEmpty)
        }
    }

    /// グループから外す。語・進捗・自作語は残る
    private func remove(_ wordIds: [String]) {
        GroupEditor(context: context).remove(wordIds: wordIds, from: group)
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }

    private func studyCard(
        plan: SessionPlan,
        summary: GroupStudy.Summary,
        words: [WordEntry]
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                countLabel("単語", summary.total)
                countLabel("学習済み", summary.learned)
                countLabel("開花", summary.blossomed)
                Spacer()
            }

            if !words.isEmpty {
                Text(planDescription(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                session = .learn(plan)
            } label: {
                Text(learnButtonTitle(plan: plan, isEmptyGroup: words.isEmpty))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.isEmpty)

            Button {
                session = .drill(words.map(\.id).shuffled())
            } label: {
                Label("ドリル（全 \(words.count) 語）", systemImage: "pencil.and.list.clipboard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .disabled(words.isEmpty)

            fillBlankButton
        }
        .cardStyle()
    }

    /// 穴埋めモード（文章の空欄に入る語を選ぶドリル）。文章の無い語は始める前に AI で作る
    private var fillBlankButton: some View {
        Button {
            session = .fillBlank(words)
        } label: {
            Label("穴埋め（全 \(words.count) 語）", systemImage: "questionmark.square.dashed")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .disabled(words.isEmpty)
    }

    private func learnButtonTitle(plan: SessionPlan, isEmptyGroup: Bool) -> String {
        if isEmptyGroup { return "学習する" }
        return plan.isEmpty ? "今日の分は完了" : "学習する（\(plan.totalCount) 語）"
    }

    private func planDescription(_ plan: SessionPlan) -> String {
        if plan.isEmpty {
            return "このグループの復習は今日はありません。ドリルならいつでも全部を確認できます（成長には反映されません）。"
        }
        var parts: [String] = []
        if !plan.reviewWordIds.isEmpty { parts.append("復習 \(plan.reviewWordIds.count) 語") }
        if !plan.newWordIds.isEmpty { parts.append("新しい単語 \(plan.newWordIds.count) 語") }
        return parts.joined(separator: "・") + "。学習した単語は庭で育ち、毎日の復習にも出てきます。"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("単語がありません", systemImage: "text.badge.plus")
        } description: {
            Text("覚えたい単語・フレーズを検索して追加しましょう。単語帳にない語もそのまま作れます。")
        } actions: {
            Button("単語を追加") { isPickingWords = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func countLabel(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(count) 語")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(count) 語")
    }
}
