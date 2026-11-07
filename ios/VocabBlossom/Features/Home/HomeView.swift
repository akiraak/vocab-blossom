import SwiftData
import SwiftUI

/// ホーム。ロゴ・今日の復習・グループのカードをまとめる（デザイン B4）。
///
/// グループを中心に使うので、起動したらすぐグループを選べ、全グループの復習もまとめてできるようにする。
/// 新しい単語はグループの「学習する」で始める（ここでは出さない）。庭の絵は統計に置く
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
                groupWordIds: Set(groups.flatMap(\.wordIds)),
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
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    reviewSection(summary)
                    groupSection(summary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .gardenBackground()
            .refreshable {
                // サーバーが無ければ何もしない（引っ張ってもすぐ戻る）
                await sync.syncNow()
            }
            // ロゴと ＋ は画面の中に置く（ナビゲーションバーの丸い背景を付けない）
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WordGroup.self) { group in
                GroupDetailView(group: group)
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

    private var header: some View {
        HStack {
            BrandWordmark()
            Spacer()
            Button {
                startCreating()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.light))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("グループを作る")
            .padding(.trailing, -10)
        }
    }

    // MARK: - 今日の復習

    private func reviewSection(_ summary: Dashboard.Summary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if summary.plan.isEmpty {
                Text("今日の復習は\n終わりました")
                    .font(.system(size: 26, weight: .light))
                    .lineSpacing(4)
                Text("新しい単語は、グループの「学習する」で始められます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                (Text("今日は ")
                    + Text("\(summary.plan.totalCount)")
                        .fontWeight(.medium)
                        .foregroundColor(Theme.accent)
                    + Text(" 語の\n復習があります"))
                    .font(.system(size: 26, weight: .light))
                    .monospacedDigit()
                    .lineSpacing(4)
            }

            HStack(spacing: 12) {
                Text("\(summary.streak) 日連続・今日 \(summary.answeredToday) 問")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !summary.plan.isEmpty {
                    Button {
                        isSessionPresented = true
                    } label: {
                        Text("復習する")
                            .font(.subheadline.weight(.medium))
                            .tracking(0.8)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 44)
                            .foregroundStyle(Theme.onAccent)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, summary.plan.isEmpty ? 18 : 6)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))

            if summary.plan.deferredReviewCount > 0 {
                Text("ほかに \(summary.plan.deferredReviewCount) 語たまっています。明日に回します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - グループ

    private func groupSection(_ summary: Dashboard.Summary) -> some View {
        let progressByWordId = progressByWordId
        let answersByGroupId = answersByGroupId
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("グループ")
                    .sectionLabel()
                Spacer()
                Text(stageCountsText(summary))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                Text("小テストの範囲や教科書の単元など、覚えたい単語・フレーズをまとめて学習できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            LazyVGrid(columns: Self.gridColumns, spacing: 10) {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        GroupCard(
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
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("グループを削除", systemImage: "trash", role: .destructive) {
                            pendingDeletion = group
                        }
                    }
                }
                createCard
            }
        }
    }

    private static let gridColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    /// 最後に置く「グループを作る」（点線の枠）
    private var createCard: some View {
        Button {
            startCreating()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title3.weight(.light))
                Text("グループを作る")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 190)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 例:「開花 6・つぼみ 9・芽 30」（種は出さない）
    private func stageCountsText(_ summary: Dashboard.Summary) -> String {
        [GrowthStage.blossom, .bud, .sprout]
            .map { "\($0.label) \(count(of: $0, in: summary))" }
            .joined(separator: "・")
    }

    private func startCreating() {
        newName = ""
        isCreating = true
    }

    private func create() {
        let group = GroupEditor(context: context).createGroup(name: newName)
        path.append(group)
    }

    private func count(of stage: GrowthStage, in summary: Dashboard.Summary) -> Int {
        summary.stageCounts
            .filter { GrowthStage(stage: $0.key) == stage }
            .values
            .reduce(0, +)
    }
}
