import SwiftUI

/// 単語帳（同梱語 + 自作語）からグループに入れる語を選ぶ。
///
/// チェックを付け外しして「完了」でまとめて反映する（新しく選んだ語は選んだ順に末尾へ入る）。
struct WordPickerView: View {
    let group: WordGroup

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.wordAssist) private var assistClient
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    /// 選んでいる語。順番を保つため配列で持つ
    @State private var selectedIds: [String] = []
    @State private var selectedSet: Set<String> = []
    @State private var showsSelectedOnly = false
    @FocusState private var isSearchFocused: Bool
    /// 見つからなかった検索語から自作語を作る
    @State private var creatingDraft: CreatingDraft?

    private struct CreatingDraft: Identifiable {
        let id = UUID()
        let draft: GroupEditor.WordDraft
    }

    private var words: [WordEntry] {
        let base = showsSelectedOnly ? store.words(ids: selectedIds) : store.allWords
        return WordStore.filter(base, query: query)
    }

    var body: some View {
        NavigationStack {
            let words = words
            List {
                Section {
                    ForEach(words) { word in
                        row(word)
                    }
                } header: {
                    Text("\(selectedIds.count) 語を選択中")
                }
            }
            .listStyle(.plain)
            .overlay {
                if words.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("選んだ単語はありません", systemImage: "checklist")
                    } else if showsSelectedOnly {
                        ContentUnavailableView.search(text: query)
                    } else {
                        notFound
                    }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "単語・意味・例文を検索"
            )
            .searchFocused($isSearchFocused)
            // 検索欄に入力している間もナビゲーションバー（キャンセル・完了）を隠さない。
            // 既定では隠れてしまい、チェックを付けたあとに押すボタンが見当たらなくなる
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle("単語帳から追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        GroupEditor(context: context).setMembership(selectedIds, for: group)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Toggle("選んだ語だけ表示", isOn: $showsSelectedOnly)
                        .toggleStyle(.button)
                }
            }
        }
        .onAppear {
            selectedIds = group.wordIds
            selectedSet = Set(group.wordIds)
        }
        #if DEBUG
        .task {
            if DebugSeed.variant == .wordPicker {
                query = DebugSeed.demoSearchQuery ?? DebugSeed.demoMissingQuery
                isSearchFocused = DebugSeed.demoSearchQuery != nil
            }
        }
        #endif
        .sheet(item: $creatingDraft) { item in
            CustomWordEditorView(mode: .pick(prefill: item.draft, onPick: select))
        }
    }

    /// 単語帳に無いときは、検索語を入れた状態で自作語のエディタを開けるようにする
    private var notFound: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContentUnavailableView {
            Label("「\(text)」は見つかりません", systemImage: "magnifyingglass")
        } description: {
            Text(assistClient == nil
                ? "単語帳に無い単語は、自分で作って追加できます。"
                : "AI が打ち間違いや変化した形を確かめ、単語帳に無い語は意味と例文を下書きします。")
        } actions: {
            Button(assistClient == nil ? "「\(text)」を自分で作って追加する" : "「\(text)」を AI で調べて追加する") {
                creatingDraft = CreatingDraft(draft: .prefilled(fromSearch: text))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func row(_ word: WordEntry) -> some View {
        let isSelected = selectedSet.contains(word.id)
        return Button {
            toggle(word.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(word.word)
                            .font(.body.weight(.medium))
                        if word.isCustom {
                            Text("マイ単語")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(word.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(word.word)、\(word.meaning)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 選択に加える（すでに選んでいれば何もしない）。「完了」でグループに反映される
    private func select(_ wordId: String) {
        if selectedSet.insert(wordId).inserted {
            selectedIds.append(wordId)
        }
    }

    private func toggle(_ wordId: String) {
        if selectedSet.remove(wordId) != nil {
            selectedIds.removeAll { $0 == wordId }
        } else {
            selectedSet.insert(wordId)
            selectedIds.append(wordId)
        }
    }
}
