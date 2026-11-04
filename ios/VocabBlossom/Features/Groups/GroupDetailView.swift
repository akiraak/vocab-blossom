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

    /// フルスクリーンで開くセッション。押した瞬間の内容で固定する
    enum GroupSession: Identifiable {
        case learn(SessionPlan)
        case drill([String])

        var id: String {
            switch self {
            case .learn: "learn"
            case .drill: "drill"
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

        List {
            Section {
                studyCard(plan: plan, summary: summary, words: words)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
                                GroupEditor(context: context).remove(wordIds: [word.id], from: group)
                            }
                        }
                    }
                } header: {
                    Text("\(words.count) 語")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .gardenBackground()
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
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
            }
        }
        #if DEBUG
        .onAppear {
            switch DebugSeed.variant {
            case .groupLearn: session = .learn(plan)
            case .groupDrill: session = .drill(words.map(\.id))
            case .wordPicker, .wordEditor, .wordEditorLoading, .wordAssistResult: isPickingWords = true
            default: break
            }
        }
        #endif
    }

    private var moreMenu: some View {
        Menu {
            Button {
                renameText = group.name
                isRenaming = true
            } label: {
                Label("名前を変更", systemImage: "pencil")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("その他")
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
        }
        .cardStyle()
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
