import SwiftUI

/// 自作語（単語帳に無い単語・フレーズ）の作成・編集。
struct CustomWordEditorView: View {
    enum Mode {
        /// 新しく作る。グループを渡すとそこにも入れる
        case create(addingTo: WordGroup?)
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
                    duplicateHint
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
                    Text("例文に単語がそのまま含まれていると、穴埋め問題でも出題されます。")
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
            if case .edit(let custom) = mode {
                draft = custom.draft
                posTouched = true
            } else {
                focusedField = .word
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

    /// 同じ綴りの同梱語があれば、自作せずにそちらを使えるよう案内する
    @ViewBuilder
    private var duplicateHint: some View {
        if !isEditing, let bundled = store.bundledWord(spelledLike: draft.word) {
            VStack(alignment: .leading, spacing: 6) {
                Text("「\(bundled.word)」（\(bundled.meaning)）は単語帳にあります。")
                if let group = targetGroup {
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
        case .edit(let custom):
            editor.update(custom, with: draft)
        }
        dismiss()
    }
}
