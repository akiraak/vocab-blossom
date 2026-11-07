import SwiftData
import SwiftUI

/// 単語詳細。意味・例文・音声に加えて、成長状態と回答履歴を見せる。
struct WordDetailView: View {
    /// 開いたときの内容。自作語は編集されうるので、表示には索引から引き直した `word` を使う
    private let original: WordEntry

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var progresses: [WordProgress]
    @Query private var logs: [AnswerLog]
    @Query(sort: \WordGroup.createdAt, order: .reverse) private var groups: [WordGroup]

    @State private var editingCustom: CustomWord?
    @State private var isConfirmingDelete = false

    init(word: WordEntry) {
        original = word
        let wordId = word.id
        _progresses = Query(filter: #Predicate<WordProgress> { $0.wordId == wordId })
        _logs = Query(
            filter: #Predicate<AnswerLog> { $0.wordId == wordId },
            sort: [SortDescriptor(\AnswerLog.answeredAt, order: .reverse)]
        )
    }

    private var word: WordEntry { store.word(id: original.id) ?? original }
    private var progress: WordProgress? { progresses.first }
    private var memberGroups: [WordGroup] { groups.filter { $0.wordIds.contains(original.id) } }
    private var stage: Int { progress?.stage ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WordCardView(word: word)
                    .cardStyle()
                statusCard
                knownButton
                if !logs.isEmpty {
                    historyCard
                }
            }
            .padding(16)
        }
        .gardenBackground()
        // スピーカーのボタンで読んでいる途中に閉じたら止める
        .onDisappear { GeminiReadAloudSpeaker.quiz.finish() }
        .navigationTitle(word.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                groupMenu
            }
            if word.isCustom {
                ToolbarItem(placement: .topBarTrailing) {
                    customMenu
                }
            }
        }
        .sheet(item: $editingCustom) { custom in
            CustomWordEditorView(mode: .edit(custom))
        }
        .confirmationDialog(
            "「\(word.word)」を削除しますか？",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("単語を削除", role: .destructive) {
                GroupEditor(context: context).deleteCustomWord(id: original.id)
                dismiss()
            }
        } message: {
            Text("すべてのグループから外れ、学習の記録も消えます。")
        }
    }

    /// グループへの出し入れ。入っているグループにはチェックが付く
    private var groupMenu: some View {
        Menu {
            if groups.isEmpty {
                Text("グループタブでグループを作ると、ここから追加できます")
            }
            ForEach(groups) { group in
                let isMember = group.wordIds.contains(original.id)
                Button {
                    let editor = GroupEditor(context: context)
                    if isMember {
                        editor.remove(wordIds: [original.id], from: group)
                    } else {
                        editor.add(wordIds: [original.id], to: group)
                    }
                } label: {
                    if isMember {
                        Label(group.name, systemImage: "checkmark")
                    } else {
                        Text(group.name)
                    }
                }
            }
        } label: {
            Image(systemName: memberGroups.isEmpty ? "folder.badge.plus" : "folder.fill")
        }
        .accessibilityLabel("グループに追加")
    }

    private var customMenu: some View {
        Menu {
            Button {
                editingCustom = GroupEditor(context: context).customWord(id: original.id)
            } label: {
                Label("編集", systemImage: "pencil")
            }
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("単語の編集・削除")
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PlantView(stage: GrowthStage(stage: stage), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GrowthStage(stage: stage).label)
                        .font(.headline)
                    Text(stage == 0 ? "まだ学習していません" : "ステージ \(stage) / \(SRS.maxStage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let progress {
                Divider()
                row("次回の復習", DateUtil.dueLabel(dueAt: progress.dueAt, now: .now))
                row("学習を始めた日", DateUtil.formatDate(progress.learnedAt))
                if progress.known {
                    row("登録", "「もう知ってる」から")
                }
            }

            if word.isCustom {
                Divider()
                row("デッキ", "マイ単語（自分で作った単語）")
            } else if let deck = store.deck(of: word.id) {
                Divider()
                row("デッキ", deck.name)
                if let level = word.level {
                    row("レベル", level.label)
                }
            }

            if !memberGroups.isEmpty {
                Divider()
                row("グループ", memberGroups.map(\.name).joined(separator: "、"))
            }
        }
        .cardStyle()
    }

    /// 学習をとばす / とばすのをやめる。1 日の枠と関係なく個別に切り替えられる
    @ViewBuilder
    private var knownButton: some View {
        if progress?.known == true {
            Button(role: .destructive) {
                LearningEngine(context: context).forget(wordId: word.id)
            } label: {
                Label("「知ってる」を取り消して学習し直す", systemImage: "arrow.uturn.left")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        } else if progress == nil {
            Button {
                LearningEngine(context: context).markKnown(wordId: word.id)
            } label: {
                Label("もう知ってる（学習をとばす）", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("回答履歴")
                .font(.headline)
            ForEach(logs.prefix(20)) { log in
                HStack(spacing: 10) {
                    Image(systemName: log.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(log.correct ? Theme.correct : Theme.incorrect)
                    Text(DateUtil.formatDate(log.answeredAt))
                        .font(.caption)
                        .monospacedDigit()
                    Text(log.quizType.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    Spacer()
                    if log.kind == .requeue {
                        Text("再出題")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if logs.count > 20 {
                Text("ほか \(logs.count - 20) 件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}
