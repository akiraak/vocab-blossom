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
    @Environment(\.dismiss) private var dismiss

    @State private var draft = GroupEditor.WordDraft()
    /// 品詞を自分で選んだか。選ぶまでは英語の入力から自動で推測する
    @State private var posTouched = false
    @FocusState private var focusedField: Field?

    private enum Field { case word, meaning, example, exampleJa }

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
                // 英語が入っていれば次は意味、意味だけなら英語を入れてもらう
                focusedField = prefill.word.isEmpty ? .word : .meaning
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
