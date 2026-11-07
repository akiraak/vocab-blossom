import SwiftUI
import SwiftData

/// グループに単語を入れる唯一の入口。1 画面の中で、単語帳（同梱語 + 自作語）を検索して選び、
/// 単語帳に無い語は AI で調べた結果をその場で選び、「追加」でまとめてグループの末尾に入れる。
///
/// グループに入っている語は「追加済み」と出すだけで、ここでは外さない（グループ詳細のスワイプで外す）。
struct WordPickerView: View {
    let group: WordGroup

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.wordAssist) private var assistClient
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var session: WordAddSession
    @FocusState private var isSearchFocused: Bool
    /// 新しく作る語の下書きを書く・直す
    @State private var editing: Editing?

    private struct Editing: Identifiable {
        let id = UUID()
        /// 直す下書き。nil なら新しく足す
        let newWordId: UUID?
        let draft: GroupEditor.WordDraft
        let posConfirmed: Bool
    }

    init(group: WordGroup) {
        self.group = group
        _session = State(initialValue: WordAddSession(addedIds: group.wordIds))
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            let words = WordStore.filter(store.allWords, query: query)
            let createAction = WordPicker.createAction(
                query: query, results: words, assistAvailable: assistClient != nil
            )
            // 何も見つからず AI もまだなら、中央に大きく案内する
            let showsNotFound = !query.isEmpty && words.isEmpty
                && session.newWords.isEmpty && session.assist == .idle
            // 同じ文字列ですでに調べた（調べている）なら、調べる行は出さない
            let showsCreateRow = !showsNotFound
                && (assistClient == nil || session.assist.text != trimmedQuery)
            List {
                if query.isEmpty {
                    Section {
                        Text("単語帳にない単語は、検索欄に入れると AI で調べて追加できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if session.assist != .idle || !session.newWords.isEmpty {
                    assistSection
                }
                if !words.isEmpty {
                    Section {
                        ForEach(words) { word in
                            wordRow(word)
                        }
                    } header: {
                        if !query.isEmpty { Text("単語帳") }
                    }
                }
                if let createAction, showsCreateRow {
                    Section {
                        createRow(createAction)
                    } footer: {
                        if let note = createAction.note {
                            Text(note)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if showsNotFound {
                    if let createAction {
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
            // 検索欄に入力している間もナビゲーションバー（キャンセル・追加）を隠さない。
            // 既定では隠れてしまい、選んだあとに押すボタンが見当たらなくなる
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onSubmit(of: .search) {
                // 単語帳に無い語を入れて確定したら、そのまま AI で調べる
                if words.isEmpty, assistClient != nil, session.assist.text != trimmedQuery {
                    runAssist()
                }
            }
            .navigationTitle("単語を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session.pickCount == 0 ? "追加" : "追加（\(session.pickCount)）") { commit() }
                        .disabled(session.pickCount == 0)
                }
            }
        }
        .task {
            #if DEBUG
            if applyDebugSeed() { return }
            #endif
            // 開いたらすぐ入力できるよう、最初から検索欄にフォーカスを当てる
            isSearchFocused = true
        }
        .sheet(item: $editing) { item in
            CustomWordEditorView(mode: .draft(item.draft, posConfirmed: item.posConfirmed) { outcome in
                apply(outcome, to: item.newWordId)
            })
        }
    }

    // MARK: - 単語帳の語

    private func wordRow(_ word: WordEntry, reason: WordAssistAPI.Reason? = nil) -> some View {
        let isAdded = session.isAdded(word.id)
        let isSelected = session.isSelected(.word(word.id))
        return Button {
            session.toggle(.word(word.id))
        } label: {
            HStack(spacing: 12) {
                checkmark(isSelected: isSelected, isAdded: isAdded)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(word.word)
                            .font(.body.weight(.medium))
                        if word.isCustom {
                            badge("マイ単語")
                        }
                    }
                    Text(word.meaningSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let label = reason?.label {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                if isAdded {
                    Text("追加済み")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityLabel(
            isAdded ? "\(word.word)、\(word.meaningSummary)、追加済み" : "\(word.word)、\(word.meaningSummary)"
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func checkmark(isSelected: Bool, isAdded: Bool) -> some View {
        Image(systemName: isAdded ? "checkmark.circle" : isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
    }

    // MARK: - AI で調べた結果

    @ViewBuilder
    private var assistSection: some View {
        Section {
            switch session.assist {
            case .idle, .done:
                EmptyView()
            case .loading(let text):
                AssistLoadingView(text: text)
            case .failed(let text, let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                Button {
                    runAssist(text: text)
                } label: {
                    Label("もう一度調べる", systemImage: "sparkles")
                }
                makeYourselfButton(text)
            }
            ForEach(session.suggestedWords) { suggested in
                if let word = store.word(id: suggested.id) {
                    wordRow(word, reason: suggested.reason)
                }
            }
            ForEach(session.newWords) { newWord in
                newWordRow(newWord)
            }
            if case .done(let text) = session.assist,
               session.suggestedWords.isEmpty, session.newWords.isEmpty {
                Text("「\(text)」の候補は見つかりませんでした。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                makeYourselfButton(text)
            }
        } header: {
            if let text = session.assist.text {
                Text("「\(text)」を AI で調べた結果")
            } else {
                Text("新しく作る単語")
            }
        } footer: {
            if !session.newWords.isEmpty {
                Text(
                    "「新しく作る」の語は、選んで「追加」するとマイ単語になります。"
                        + "「置き換える」の語は、同じ綴りのマイ単語の内容をこの内容に置き換えます。"
                        + "意味が複数あるときは、入れる意味だけにチェックを付けてください。違うところは「直す」で直せます。"
                )
            }
        }
    }

    private func newWordRow(_ newWord: WordAddSession.NewWord) -> some View {
        let isSelected = session.isSelected(.newWord(newWord.id))
        let draft = newWord.draft
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    session.toggle(.newWord(newWord.id))
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        checkmark(isSelected: isSelected, isAdded: false)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(draft.word)
                                    .font(.body.weight(.semibold))
                                if !newWord.hasMultipleSenses {
                                    Text(draft.pos.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                badge(replacesCustomWord(draft) ? "置き換える" : "新しく作る")
                            }
                            if !newWord.hasMultipleSenses {
                                senseText(draft.primarySense)
                            }
                            if let label = newWord.reason?.label {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(newWordLabel(newWord))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

                if newWord.hasMultipleSenses {
                    ForEach(Array(draft.senses.enumerated()), id: \.offset) { index, sense in
                        senseRow(newWord, sense: sense, index: index, wordSelected: isSelected)
                    }
                }
            }

            Button("直す") {
                // 入れる意味だけをエディタに渡す（外した意味は直す対象にしない）
                let editable = newWord.committedDraft ?? draft
                editing = Editing(newWordId: newWord.id, draft: editable, posConfirmed: true)
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    /// 意味が複数あるときの 1 つ分。意味ごとに入れる・入れないを選べる
    private func senseRow(
        _ newWord: WordAddSession.NewWord, sense: WordSense, index: Int, wordSelected: Bool
    ) -> some View {
        let isIncluded = wordSelected && newWord.isIncluded(senseAt: index)
        return Button {
            session.toggleSense(newWord.id, at: index)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isIncluded ? Theme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sense.pos.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(sense.meaning)
                            .font(.subheadline)
                    }
                    if !sense.example.isEmpty {
                        Text(sense.example)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sense.pos.label)、\(sense.meaning)")
        .accessibilityAddTraits(isIncluded ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func senseText(_ sense: WordSense) -> some View {
        Text(sense.meaning)
            .font(.subheadline)
        if !sense.example.isEmpty {
            Text(sense.example)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func newWordLabel(_ newWord: WordAddSession.NewWord) -> String {
        let draft = newWord.draft
        let senses = draft.senses.map { "\($0.pos.label)、\($0.meaning)" }.joined(separator: "、")
        return "\(draft.word)、\(senses)、\(replacesCustomWord(draft) ? "マイ単語を置き換える" : "新しく作る")"
    }

    /// 同じ綴りのマイ単語がある（確定するとそのマイ単語の内容を置き換える）
    private func replacesCustomWord(_ draft: GroupEditor.WordDraft) -> Bool {
        let spelling = WordStore.normalizedSpelling(draft.word)
        return store.customWords.contains { WordStore.normalizedSpelling($0.word) == spelling }
    }

    private func makeYourselfButton(_ text: String) -> some View {
        Button {
            startMakingYourself(text)
        } label: {
            Label("「\(text)」を自分で作る", systemImage: "square.and.pencil")
        }
    }

    // MARK: - 単語帳に無いとき

    /// 単語帳に無いときは、AI で調べる（使えなければ自分で作る）よう大きく案内する
    private func notFound(_ action: WordPicker.CreateAction) -> some View {
        ContentUnavailableView {
            Label("「\(action.text)」は単語帳にありません", systemImage: "magnifyingglass")
        } description: {
            Text(assistClient == nil
                ? "単語帳に無い単語は、自分で作って追加できます。"
                : "AI が打ち間違いや変化した形を確かめ、単語帳に無い語は意味と例文を下書きします。")
        } actions: {
            Button(action.title) { startCreating(action) }
                .buttonStyle(.capsule)
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
        if assistClient == nil {
            startMakingYourself(action.text)
        } else {
            runAssist(text: action.text)
        }
    }

    private func startMakingYourself(_ text: String) {
        editing = Editing(newWordId: nil, draft: .prefilled(fromSearch: text), posConfirmed: false)
    }

    private func runAssist(text: String? = nil) {
        let text = text ?? trimmedQuery
        guard !text.isEmpty, let assistClient else { return }
        session.startAssist(text: text)
        Task {
            do {
                let response = try await assistClient.suggest(text)
                session.finishAssist(text: text, candidates: response.candidates)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                session.failAssist(text: text, message: message)
            }
        }
    }

    private func apply(_ outcome: CustomWordEditorView.DraftOutcome, to newWordId: UUID?) {
        switch (outcome, newWordId) {
        case (.draft(let draft), .some(let id)):
            session.updateNewWord(id, with: draft)
        case (.draft(let draft), .none):
            session.addNewWord(draft)
        case (.bundled(let wordId), .some(let id)):
            session.replaceNewWord(id, withWord: wordId)
        case (.bundled(let wordId), .none):
            session.select(.word(wordId))
        }
    }

    // MARK: - 確定

    private func commit() {
        let editor = GroupEditor(context: context)
        // 同じ綴りのマイ単語があれば、新しく作らずに置き換える（マイ単語は綴りごとに 1 つ）
        let wordIds = session.commit { editor.upsertCustomWord($0).wordId }
        // 寄せて消した同じ綴りのマイ単語を一覧から選んでいたときは、その ID を入れない
        let existing = wordIds.filter { !CustomWord.isCustom($0) || editor.customWord(id: $0) != nil }
        editor.add(wordIds: existing, to: group)
        dismiss()
    }

    #if DEBUG
    /// 画面確認用の状態にする。したら true
    private func applyDebugSeed() -> Bool {
        switch DebugSeed.variant {
        case .wordPicker:
            query = DebugSeed.demoSearchQuery ?? DebugSeed.demoMissingQuery
            isSearchFocused = DebugSeed.demoSearchQuery != nil
        case .wordEditorLoading:
            query = DebugSeed.demoMissingQuery
            session.startAssist(text: DebugSeed.demoMissingQuery)
        case .wordAssistResult:
            query = DebugSeed.demoMissingQuery
            session.startAssist(text: DebugSeed.demoMissingQuery)
            session.finishAssist(text: DebugSeed.demoMissingQuery, candidates: DebugSeed.demoCandidates)
        case .wordEditor:
            query = DebugSeed.demoMissingQuery
            editing = Editing(newWordId: nil, draft: DebugSeed.demoDraft, posConfirmed: false)
        case .wordEditorSenses:
            query = DebugSeed.demoMissingQuery
            let draft = WordAddSession.NewWord(candidates: DebugSeed.demoCandidates).draft
            editing = Editing(newWordId: nil, draft: draft, posConfirmed: true)
        default:
            return false
        }
        return true
    }
    #endif
}
