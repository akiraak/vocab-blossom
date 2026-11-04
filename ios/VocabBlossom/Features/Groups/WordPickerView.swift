import SwiftUI

/// グループに単語を入れる唯一の入口。単語帳（同梱語 + 自作語）を検索して選び、
/// 単語帳に無い語はその場で（AI で調べて）作って選択に加える。
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
            let createAction = showsSelectedOnly
                ? nil
                : WordPicker.createAction(query: query, results: words, assistAvailable: assistClient != nil)
            List {
                Section {
                    if query.isEmpty, !showsSelectedOnly {
                        Text("単語帳にない単語は、検索欄に入れるとここから作れます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(words) { word in
                        row(word)
                    }
                } header: {
                    Text("\(selectedIds.count) 語を選択中")
                }
                if let createAction, !words.isEmpty {
                    Section {
                        createRow(createAction)
                    } footer: {
                        if let note = createAction.note {
                            Text(note)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if words.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("選んだ単語はありません", systemImage: "checklist")
                    } else if let createAction {
                        notFound(createAction)
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "英語か意味で検索（単語帳にない語も追加できます）"
            )
            .searchFocused($isSearchFocused)
            // 検索欄に入力している間もナビゲーションバー（キャンセル・完了）を隠さない。
            // 既定では隠れてしまい、チェックを付けたあとに押すボタンが見当たらなくなる
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle("単語を追加")
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
        .task {
            #if DEBUG
            switch DebugSeed.variant {
            case .wordPicker:
                query = DebugSeed.demoSearchQuery ?? DebugSeed.demoMissingQuery
                isSearchFocused = DebugSeed.demoSearchQuery != nil
                return
            case .wordEditor, .wordEditorLoading:
                query = DebugSeed.demoMissingQuery
                creatingDraft = CreatingDraft(draft: DebugSeed.demoDraft)
                return
            default:
                break
            }
            #endif
            // 開いたらすぐ入力できるよう、最初から検索欄にフォーカスを当てる
            isSearchFocused = true
        }
        .sheet(item: $creatingDraft) { item in
            CustomWordEditorView(mode: .create(prefill: item.draft, onPick: select))
        }
    }

    /// 単語帳に無いときは、検索語を入れた状態で自作語のエディタを開けるよう大きく案内する
    private func notFound(_ action: WordPicker.CreateAction) -> some View {
        ContentUnavailableView {
            Label("「\(action.text)」は見つかりません", systemImage: "magnifyingglass")
        } description: {
            Text(assistClient == nil
                ? "単語帳に無い単語は、自分で作って追加できます。"
                : "AI が打ち間違いや変化した形を確かめ、単語帳に無い語は意味と例文を下書きします。")
        } actions: {
            Button(action.title) { startCreating(action) }
                .buttonStyle(.borderedProminent)
        }
    }

    /// 検索結果があるときは、一覧の最後に控えめに出す（探している語が一覧に無いとき用）
    private func createRow(_ action: WordPicker.CreateAction) -> some View {
        Button {
            startCreating(action)
        } label: {
            Label(action.title, systemImage: assistClient == nil ? "square.and.pencil" : "sparkles")
        }
    }

    private func startCreating(_ action: WordPicker.CreateAction) {
        creatingDraft = CreatingDraft(draft: .prefilled(fromSearch: action.text))
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
