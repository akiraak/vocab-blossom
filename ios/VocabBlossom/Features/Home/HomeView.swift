import SwiftData
import SwiftUI

/// ホーム。今日の復習・グループ・庭をまとめる。
///
/// グループを中心に使うので、起動したらすぐグループを選べ、全グループの復習もまとめてできるようにする。
/// 新しい単語はグループの「学習する」で始める（ここでは出さない）
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync
    @Query private var progresses: [WordProgress]
    @Query private var logs: [AnswerLog]
    @Query(sort: \WordGroup.createdAt, order: .reverse) private var groups: [WordGroup]
    @Query private var groupAnswers: [GroupAnswerLog]

    @State private var isSessionPresented = false
    @State private var isCreating = false
    @State private var newName = ""
    @State private var path: [WordGroup] = []
    @State private var pendingDeletion: WordGroup?

    private var summary: Dashboard.Summary {
        Dashboard.summary(
            Dashboard.Input(
                now: .now,
                progress: progresses.map(\.snapshot),
                learnedAtByWordId: Dictionary(
                    progresses.map { ($0.wordId, $0.learnedAt) },
                    uniquingKeysWith: { first, _ in first }
                ),
                logs: logs.map(\.snapshot),
                reviewLimitPerDay: StudyLimits.reviewsPerDay
            )
        )
    }

    private var progressByWordId: [String: ProgressSnapshot] {
        Dictionary(
            progresses.map { ($0.wordId, $0.snapshot) }, uniquingKeysWith: { first, _ in first }
        )
    }

    private var answersByGroupId: [UUID: [GroupStudy.Answer]] {
        Dictionary(grouping: groupAnswers, by: \.groupId).mapValues { $0.map(\.snapshot) }
    }

    var body: some View {
        let summary = summary
        NavigationStack(path: $path) {
            List {
                Section {
                    reviewCard(summary)
                        .cardRow()
                }
                Section {
                    if groups.isEmpty {
                        emptyGroups
                    } else {
                        groupRows
                    }
                } header: {
                    Text("グループ")
                }
                Section {
                    gardenCard(summary)
                        .cardRow()
                }
            }
            .scrollContentBackground(.hidden)
            .gardenBackground()
            .refreshable {
                // サーバーが無ければ何もしない（引っ張ってもすぐ戻る）
                await sync.syncNow()
            }
            .navigationTitle("vocab-blossom")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WordGroup.self) { group in
                GroupDetailView(group: group)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startCreating()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("グループを作る")
                }
            }
            .alert("新しいグループ", isPresented: $isCreating) {
                TextField("例: 小テスト Unit 3", text: $newName)
                Button("作成") { create() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("グループの名前を入力してください")
            }
            .confirmationDialog(
                "「\(pendingDeletion?.name ?? "")」を削除しますか？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("グループを削除", role: .destructive) {
                    if let group = pendingDeletion {
                        GroupEditor(context: context).delete(group)
                    }
                    pendingDeletion = nil
                }
            } message: {
                Text("中の単語と学習の記録は消えません。自分で作った単語は設定の「マイ単語」に残ります。")
            }
            .fullScreenCover(isPresented: $isSessionPresented) {
                SessionView(plan: summary.plan, closeTitle: "ホームにもどる")
            }
        }
        #if DEBUG
        .onAppear {
            if DebugSeed.autoStartSession { isSessionPresented = true }
        }
        .task(id: groups.count) {
            // ダミーデータは起動後に入るので、グループが現れた時点で開く
            if DebugSeed.opensFirstGroup, path.isEmpty, let group = groups.first {
                path = [group]
            }
        }
        #endif
    }

    // MARK: - 今日の復習

    private func reviewCard(_ summary: Dashboard.Summary) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日の復習")
                    .font(.headline)
                Spacer()
                Label("\(summary.streak) 日", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("ストリーク \(summary.streak) 日")
                Text("今日の回答 \(summary.answeredToday) 問")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if summary.plan.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("今日の復習は終わりました", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.correct)
                    Text("新しい単語は、グループの「学習する」で始められます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("期限が来た単語をまとめて復習します。どのグループの単語も出てきます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if summary.plan.deferredReviewCount > 0 {
                    Text("ほかに \(summary.plan.deferredReviewCount) 語たまっています。明日に回します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    isSessionPresented = true
                } label: {
                    Text("復習する（\(summary.plan.totalCount) 語）")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardStyle()
    }

    // MARK: - グループ

    private var groupRows: some View {
        let progressByWordId = progressByWordId
        let answersByGroupId = answersByGroupId
        return ForEach(groups) { group in
            NavigationLink(value: group) {
                GroupRow(
                    group: group,
                    summary: GroupStudy.summary(
                        wordIds: group.wordIds,
                        progressByWordId: progressByWordId,
                        now: .now
                    ),
                    activity: GroupStudy.activity(
                        wordIds: group.wordIds,
                        answers: answersByGroupId[group.id] ?? []
                    )
                )
            }
            .swipeActions {
                Button("削除", role: .destructive) { pendingDeletion = group }
            }
        }
    }

    private var emptyGroups: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("グループがありません", systemImage: "folder.badge.plus")
                .font(.subheadline.weight(.semibold))
            Text("小テストの範囲や教科書の単元など、覚えたい単語・フレーズをまとめて学習できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("グループを作る") { startCreating() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }

    private func startCreating() {
        newName = ""
        isCreating = true
    }

    private func create() {
        let group = GroupEditor(context: context).createGroup(name: newName)
        path.append(group)
    }

    // MARK: - 庭

    private func gardenCard(_ summary: Dashboard.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("あなたの庭")
                    .font(.headline)
                Spacer()
                Text("覚えた語 \(summary.learnedCount) 語")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GardenView(
                stages: summary.gardenStages,
                overflow: max(0, summary.learnedCount - summary.gardenStages.count)
            )
            HStack(spacing: 12) {
                ForEach(GrowthStage.allCases.reversed(), id: \.self) { stage in
                    if stage != .seed {
                        stageChip(stage, count: count(of: stage, in: summary))
                    }
                }
            }
        }
        .cardStyle()
    }

    private func stageChip(_ stage: GrowthStage, count: Int) -> some View {
        HStack(spacing: 4) {
            PlantView(stage: stage, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(stage.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.label) \(count) 語")
    }

    private func count(of stage: GrowthStage, in summary: Dashboard.Summary) -> Int {
        summary.stageCounts
            .filter { GrowthStage(stage: $0.key) == stage }
            .values
            .reduce(0, +)
    }
}

private extension View {
    /// カードの見た目のまま List の行に置く（行の背景・余白を消す）
    func cardRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}
