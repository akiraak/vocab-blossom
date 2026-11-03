import SwiftUI

/// 自作語（単語帳に無い単語・フレーズ）の作成・編集。
struct CustomWordEditorView: View {
    enum Mode {
        /// 新しく作る。グループを渡すとそこにも入れる
        case create(addingTo: WordGroup?)
        /// 「単語帳から追加」の画面から作る。入力済みの下書きで開き、作った語（または案内した同梱語）の
        /// ID を `onPick` で返す。グループへの反映は呼び出し側の選択に任せる
        case pick(prefill: GroupEditor.WordDraft, onPick: (String) -> Void)
        case edit(CustomWord)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.wordAssist) private var assistClient
    @Environment(\.dismiss) private var dismiss

    @State private var draft = GroupEditor.WordDraft()
    /// 品詞を自分で選んだか。選ぶまでは英語の入力から自動で推測する
    @State private var posTouched = false
    @FocusState private var focusedField: Field?
    @State private var assist: AssistState = .idle

    private enum Field { case word, meaning, example, exampleJa }

    /// AI チェックの状態。`text` は AI に送った文字列（入力が変わったら調べ直せるようにする）
    private enum AssistState: Equatable {
        case idle
        case loading(text: String)
        case done(text: String, candidates: [WordAssistAPI.Candidate])
        case failed(text: String, message: String)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var targetGroup: WordGroup? {
        if case .create(let group) = mode { return group }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("英語（例: take care of）", text: $draft.word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .word)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .meaning }
                    TextField("意味（例: 〜の世話をする）", text: $draft.meaning)
                        .focused($focusedField, equals: .meaning)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .example }
                    Picker("品詞", selection: posBinding) {
                        ForEach(PartOfSpeech.allCases, id: \.self) { pos in
                            Text(pos.label).tag(pos)
                        }
                    }
                } header: {
                    Text("必須")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        posHint
                        duplicateHint
                    }
                }

                if showsAssist {
                    assistSection
                }

                Section {
                    TextField("例文（英語）", text: $draft.example, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .example)
                    TextField("例文の訳", text: $draft.exampleJa, axis: .vertical)
                        .focused($focusedField, equals: .exampleJa)
                } header: {
                    Text("例文（任意）")
                } footer: {
                    exampleHint
                }
            }
            .navigationTitle(isEditing ? "単語を編集" : "単語を作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "追加") { save() }
                        .disabled(!draft.isValid)
                }
            }
        }
        .onAppear {
            switch mode {
            case .edit(let custom):
                draft = custom.draft
                posTouched = true
            case .pick(let prefill, _):
                draft = prefill
                if showsAssist {
                    // 単語帳に無かった検索語なので、まず AI に打ち間違い・変化形・意味を聞く
                    runAssist()
                } else {
                    // 英語が入っていれば次は意味、意味だけなら英語を入れてもらう
                    focusedField = prefill.word.isEmpty ? .word : .meaning
                }
            case .create:
                focusedField = .word
                #if DEBUG
                if DebugSeed.variant == .wordEditor { draft = DebugSeed.demoDraft }
                #endif
            }
        }
        .onChange(of: draft.word) { _, word in
            if !posTouched { draft.pos = GroupEditor.WordDraft.guessedPos(for: word) }
        }
    }

    private var posBinding: Binding<PartOfSpeech> {
        Binding(
            get: { draft.pos },
            set: {
                draft.pos = $0
                posTouched = true
            }
        )
    }

    /// 品詞が自動で決めたままなら見直しを促す（名詞のまま動詞を登録すると、
    /// 誤答肢が名詞ばかりになり、穴埋めでは文法だけで答えが分かってしまう）
    @ViewBuilder
    private var posHint: some View {
        if !posTouched, !draft.trimmed.word.isEmpty {
            Text("品詞は自動で「\(draft.pos.label)」にしています。違うときは選び直してください。選択肢は同じ品詞の語から選ばれます。")
        }
    }

    /// 例文に単語が見つからないときは、穴埋め問題にならないことを伝える
    @ViewBuilder
    private var exampleHint: some View {
        if draft.exampleMissesWord {
            Label {
                Text("例文に「\(draft.trimmed.word)」が見つからないため、穴埋め問題にはなりません。英語と例文の綴り、品詞を見直してください。")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        } else {
            Text("例文に単語が含まれていると、穴埋め問題でも出題されます。")
        }
    }

    /// 同じ綴りの同梱語があれば、自作せずにそちらを使えるよう案内する
    @ViewBuilder
    private var duplicateHint: some View {
        if !isEditing, let bundled = store.bundledWord(spelledLike: draft.word) {
            VStack(alignment: .leading, spacing: 6) {
                Text("「\(bundled.word)」（\(bundled.meaning)）は単語帳にあります。")
                if case .pick(_, let onPick) = mode {
                    Button("単語帳の「\(bundled.word)」を選ぶ") {
                        onPick(bundled.id)
                        dismiss()
                    }
                    .font(.footnote.weight(.semibold))
                } else if let group = targetGroup {
                    Button("単語帳の「\(bundled.word)」をグループに追加する") {
                        GroupEditor(context: context).add(wordIds: [bundled.id], to: group)
                        dismiss()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    // MARK: - AI チェック

    /// 新しく作るときだけ（編集では同梱語への置き換えができないので出さない）
    private var showsAssist: Bool {
        assistClient != nil && !isEditing
    }

    /// AI に送る文字列。英語があれば英語、無ければ意味（日本語から探す）
    private var assistText: String {
        let value = draft.trimmed
        return value.word.isEmpty ? value.meaning : value.word
    }

    @ViewBuilder
    private var assistSection: some View {
        Section {
            switch assist {
            case .idle:
                assistButton("AI で調べる")
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("AI で調べています…")
                        .foregroundStyle(.secondary)
                }
            case .done(let text, let candidates):
                ForEach(candidates) { candidate in
                    candidateRow(candidate)
                }
                if text != assistText {
                    assistButton("「\(assistText)」で調べ直す")
                }
            case .failed(_, let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                assistButton("もう一度調べる")
            }
        } header: {
            Text("AI チェック")
        } footer: {
            Text("打ち間違いや変化した形なら単語帳の語を案内し、単語帳に無い語は意味・品詞・例文を下書きします。内容は確かめてから追加してください。")
        }
    }

    private func assistButton(_ title: String) -> some View {
        Button {
            runAssist()
        } label: {
            Label(title, systemImage: "sparkles")
        }
        .disabled(assistText.isEmpty)
    }

    @ViewBuilder
    private func candidateRow(_ candidate: WordAssistAPI.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(candidate.word)
                    .font(.body.weight(.semibold))
                Text(candidate.pos.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if candidate.bundled != nil {
                    Text("単語帳にあります")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(candidate.bundled?.meaning ?? candidate.meaning)
                .font(.subheadline)
            if let reason = candidate.reason.label {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if candidate.bundled == nil, !candidate.example.isEmpty {
                Text(candidate.example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            candidateAction(candidate)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    /// 同梱語なら（自作せずに）それを使う。無ければ下書きに入れる
    @ViewBuilder
    private func candidateAction(_ candidate: WordAssistAPI.Candidate) -> some View {
        if let bundled = candidate.bundled {
            if case .pick(_, let onPick) = mode {
                Button("単語帳の「\(bundled.word)」を選ぶ") {
                    onPick(bundled.id)
                    dismiss()
                }
            } else if let group = targetGroup {
                Button("単語帳の「\(bundled.word)」をグループに追加する") {
                    GroupEditor(context: context).add(wordIds: [bundled.id], to: group)
                    dismiss()
                }
            } else {
                Text("単語帳にあるので、作らなくても学習できます")
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("この内容を入れる") {
                posTouched = true
                draft = draft.applying(candidate, onlyEmpty: false)
            }
        }
    }

    private func runAssist() {
        guard let assistClient else { return }
        let text = assistText
        guard !text.isEmpty else { return }
        assist = .loading(text: text)
        Task {
            do {
                let response = try await assistClient.suggest(text)
                assist = .done(text: text, candidates: response.candidates)
                autofill(from: response.candidates)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                assist = .failed(text: text, message: message)
            }
        }
    }

    /// 入力がそのまま正しい単語帳に無い語なら、空いている欄だけ AI の下書きで埋める。
    /// 打ち間違い・変化形・日本語からの候補は、どれにするか選んでもらう
    private func autofill(from candidates: [WordAssistAPI.Candidate]) {
        guard let first = candidates.first, first.reason == .exact, first.bundled == nil else { return }
        let keptPos = posTouched ? draft.pos : nil
        posTouched = true
        var filled = draft.applying(first, onlyEmpty: true)
        if let keptPos { filled.pos = keptPos }
        draft = filled
    }

    private func save() {
        let editor = GroupEditor(context: context)
        switch mode {
        case .create(let group):
            editor.createCustomWord(draft, addingTo: group)
        case .pick(_, let onPick):
            onPick(editor.createCustomWord(draft).wordId)
        case .edit(let custom):
            editor.update(custom, with: draft)
        }
        dismiss()
    }
}
