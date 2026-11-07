import SwiftData
import SwiftUI

/// グループの中身と、グループ単位の学習（SRS 共有）/ ドリル（進捗を動かさない）の入口。
struct GroupDetailView: View {
    let group: WordGroup

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(AppSettings.self) private var settings
    @Query private var progresses: [WordProgress]
    /// このグループの問題に答えた記録（回答数・達成度）
    @Query private var groupAnswers: [GroupAnswerLog]

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
        /// グループの単語を順に読み上げる（学習の記録には残さない）
        case readAloud([WordEntry])

        var id: String {
            switch self {
            case .learn: "learn"
            case .drill: "drill"
            case .fillBlank: "fill-blank"
            case .readAloud: "read-aloud"
            }
        }
    }

    init(group: WordGroup) {
        self.group = group
        let groupId = group.id
        _groupAnswers = Query(filter: #Predicate<GroupAnswerLog> { $0.groupId == groupId })
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
                progress: progresses.map(\.snapshot)
            )
        )
        let summary = GroupStudy.summary(
            wordIds: words.map(\.id),
            progressByWordId: progressByWordId.mapValues(\.snapshot),
            now: .now
        )
        let activity = GroupStudy.activity(wordIds: words.map(\.id), answers: groupAnswers.map(\.snapshot))

        List(selection: $selection) {
            if !isSelecting {
                Section {
                    studyCard(plan: plan, summary: summary, activity: activity, words: words)
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
                // グループ名は画面の中に細字で大きく出すので、バーには出さない（戻るボタンの文字には使う）
                ToolbarItem(placement: .principal) { Text("") }
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
        .task(id: words.first) {
            // 最初の語の音声を先に取っておき、読み上げを押したらすぐ鳴らす（端末に残っていれば何もしない）
            GeminiReadAloudSpeaker.shared.warmUp(for: words)
            // 「学習する」で最初に出す語の音声も取っておく（最初のカードが内蔵の声にならないように）
            if settings.soundEnabled {
                GeminiReadAloudSpeaker.quiz.prefetch(learningWarmUpLines(plan))
            }
        }
        .fullScreenCover(item: $session) { session in
            switch session {
            case .learn(let plan):
                SessionView(
                    plan: plan,
                    closeTitle: "グループにもどる",
                    group: GroupAnswerContext(groupId: group.id, source: .learning)
                )
            case .drill(let wordIds):
                SessionView(
                    drillWordIds: wordIds,
                    closeTitle: "グループにもどる",
                    group: GroupAnswerContext(groupId: group.id, source: .drill)
                )
            case .fillBlank(let words):
                FillBlankSessionView(words: words, closeTitle: "グループにもどる", groupId: group.id)
                    #if DEBUG
                    .debugPassagePreparation()
                    #endif
            case .readAloud(let words):
                ReadAloudView(groupName: group.name, words: words)
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
            case .groupReadAloud: session = .readAloud(words)
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
            Image(systemName: "ellipsis")
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

    /// 上の部分: 細字のグループ名と数字、育ち具合の色面に次の学習と「学習する」、ドリル・穴埋め・読み上げ（デザイン B4）
    private func studyCard(
        plan: SessionPlan,
        summary: GroupStudy.Summary,
        activity: GroupStudy.Activity,
        words: [WordEntry]
    ) -> some View {
        let growth = GroupStudy.growth(summary: summary, activity: activity)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.name)
                    .font(.system(size: 28, weight: .light))
                    .accessibilityAddTraits(.isHeader)
                Text(numbersLine(summary: summary, activity: activity))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("次の学習")
                        .font(.caption)
                        .tracking(1.4)
                        .foregroundStyle(Theme.tintText)
                    Text(nextStudyText(plan: plan, isEmptyGroup: words.isEmpty))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 90)
                Button {
                    session = .learn(plan)
                } label: {
                    Text("学習する")
                        .font(.subheadline.weight(.medium))
                        .tracking(0.8)
                        .padding(.horizontal, 26)
                        .frame(minHeight: 46)
                        .foregroundStyle(Theme.onAccent)
                        .background(plan.isEmpty ? Color.secondary.opacity(0.4) : Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(plan.isEmpty)
                if !words.isEmpty {
                    Text(planNote(plan))
                        .font(.caption2)
                        .foregroundStyle(Theme.tintText)
                        .padding(.trailing, 90)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                PlantIllustration(stage: growth, height: 120)
            }
            .background(growth.tint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))

            HStack(spacing: 10) {
                modeButton("ドリル", systemImage: "arrow.triangle.2.circlepath") {
                    session = .drill(words.map(\.id).shuffled())
                }
                // 穴埋め: 文章の空欄に入る語を選ぶドリル。文章の無い語は始める前に AI で作る
                modeButton("穴埋め", systemImage: "rectangle.and.pencil.and.ellipsis") {
                    session = .fillBlank(words)
                }
                // 読み上げ: 単語 → 品詞と意味 → 例文 → 和訳を順に読む。ループもできる
                modeButton("読み上げ", systemImage: "speaker.wave.2") {
                    session = .readAloud(words)
                }
            }
            .disabled(words.isEmpty)
        }
        .padding(.horizontal, 4)
    }

    /// ドリル・穴埋め・読み上げのボタン（薄い色面）
    private func modeButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.light))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.tintSprout, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 例:「13 語・学習済み 11・開花 3・達成 72%・回答 41」
    private func numbersLine(summary: GroupStudy.Summary, activity: GroupStudy.Activity) -> String {
        var parts = ["\(summary.total) 語", "学習済み \(summary.learned)", "開花 \(summary.blossomed)"]
        if let percent = GroupActivityText.percent(activity), activity.answerCount > 0 {
            parts.append("達成 \(percent)%")
        }
        parts.append("回答 \(activity.answerCount)")
        return parts.joined(separator: "・")
    }

    /// 「学習する」で最初に出す 2 語の、先に取っておく文（単語とすべての意味の例文）
    private func learningWarmUpLines(_ plan: SessionPlan) -> [[ReadAloudLine]] {
        let words = words
        return (plan.reviewWordIds + plan.newWordIds).prefix(2)
            .compactMap { id in words.first { $0.id == id } }
            .map(ReadAloudScript.learningPrefetchLines)
    }

    private func nextStudyText(plan: SessionPlan, isEmptyGroup: Bool) -> String {
        if isEmptyGroup { return "単語を追加すると学習できます" }
        if plan.isEmpty { return "今日の分は完了" }
        var parts: [String] = []
        if !plan.reviewWordIds.isEmpty { parts.append("復習 \(plan.reviewWordIds.count) 語") }
        if !plan.newWordIds.isEmpty { parts.append("新しい単語 \(plan.newWordIds.count) 語") }
        return parts.joined(separator: " ＋ ")
    }

    private func planNote(_ plan: SessionPlan) -> String {
        plan.isEmpty
            ? "復習は今日はありません。ドリルならいつでも全部を確認できます（成長には反映されません）。"
            : "学習した単語は庭で育ち、毎日の復習にも出てきます。"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("単語がありません", systemImage: "text.badge.plus")
        } description: {
            Text("覚えたい単語・フレーズを検索して追加しましょう。単語帳にない語もそのまま作れます。")
        } actions: {
            Button("単語を追加") { isPickingWords = true }
                .buttonStyle(.capsule)
        }
    }
}
