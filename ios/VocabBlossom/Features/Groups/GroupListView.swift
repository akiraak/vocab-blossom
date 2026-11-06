import SwiftData
import SwiftUI

/// グループ一覧。自分で決めた範囲（小テスト・教科書の Unit など）をまとめて覚えるための入口。
struct GroupListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncService.self) private var sync
    @Query(sort: \WordGroup.createdAt, order: .reverse) private var groups: [WordGroup]
    @Query private var progresses: [WordProgress]
    @Query private var groupAnswers: [GroupAnswerLog]

    @State private var isCreating = false
    @State private var newName = ""
    @State private var path: [WordGroup] = []
    @State private var pendingDeletion: WordGroup?

    private var progressByWordId: [String: ProgressSnapshot] {
        Dictionary(
            progresses.map { ($0.wordId, $0.snapshot) }, uniquingKeysWith: { first, _ in first }
        )
    }

    private var answersByGroupId: [UUID: [GroupStudy.Answer]] {
        Dictionary(grouping: groupAnswers, by: \.groupId).mapValues { $0.map(\.snapshot) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if groups.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .gardenBackground()
            .navigationTitle("グループ")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WordGroup.self) { group in
                GroupDetailView(group: group)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        isCreating = true
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
                Text("中の単語と学習の記録は消えません。自分で作った単語は単語帳の「マイ単語」に残ります。")
            }
        }
        #if DEBUG
        .task(id: groups.count) {
            // ダミーデータは起動後に入るので、グループが現れた時点で開く
            if DebugSeed.opensFirstGroup, path.isEmpty, let group = groups.first {
                path = [group]
            }
        }
        #endif
    }

    private var list: some View {
        let progressByWordId = progressByWordId
        let answersByGroupId = answersByGroupId
        return List {
            ForEach(groups) { group in
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
        .scrollContentBackground(.hidden)
        .refreshable {
            // サーバーが無ければ何もしない（引っ張ってもすぐ戻る）
            await sync.syncNow()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("グループがありません", systemImage: "folder.badge.plus")
        } description: {
            Text("小テストの範囲や教科書の単元など、覚えたい単語・フレーズをまとめて学習できます。")
        } actions: {
            Button("グループを作る") {
                newName = ""
                isCreating = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func create() {
        let group = GroupEditor(context: context).createGroup(name: newName)
        path.append(group)
    }
}

/// 一覧の 1 行。語数と育ち具合、今日の復習があるか、問題をこなした回数と達成度を見せる。
struct GroupRow: View {
    let group: WordGroup
    let summary: GroupStudy.Summary
    let activity: GroupStudy.Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body.weight(.medium))
                Text("\(summary.total) 語・学習済み \(summary.learned) 語")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // まだ答えていないグループは今までの表示のまま
                if activity.answerCount > 0 {
                    activityLine
                }
            }
            Spacer(minLength: 8)
            if summary.due > 0 {
                Text("復習 \(summary.due)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var activityLine: some View {
        HStack(spacing: 8) {
            Text(GroupActivityText.line(activity))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let achievement = activity.achievement {
                ProgressView(value: achievement)
                    .tint(Theme.accent)
                    .frame(maxWidth: 80)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 回答数・達成度の文言。一覧と詳細で同じ書き方にする
enum GroupActivityText {
    /// 例:「回答 42 回・達成 67%」
    static func line(_ activity: GroupStudy.Activity) -> String {
        var text = "回答 \(activity.answerCount) 回"
        if let percent = percent(activity) { text += "・達成 \(percent)%" }
        return text
    }

    /// 切り捨てる（1 語でも残っていれば 100% にしない）
    static func percent(_ activity: GroupStudy.Activity) -> Int? {
        activity.achievement.map { Int(($0 * 100).rounded(.down)) }
    }
}
