import SwiftUI
import SwiftData

/// 自作語（単語帳に無い単語・フレーズ）の作成・編集。
///
/// 1 語に品詞の違う意味を複数持てる（commute の「動詞: 通勤する」「名詞: 通勤」）。
/// 意味ごとに品詞・意味・例文・訳を入れ、「意味を追加」「この意味を消す」で増減する（最低 1 つ）
struct CustomWordEditorView: View {
    enum Mode {
        /// 新しく作る語の下書きを書く・直す。「単語を追加」の画面から開き、結果を `onDone` で返す。
        /// 自作語はまだ作らない（「単語を追加」の「追加」で作る）。
        /// `posConfirmed` は品詞が決まっている（AI の候補など）か。決まっていなければ英語から推測する
        case draft(GroupEditor.WordDraft, posConfirmed: Bool, onDone: (DraftOutcome) -> Void)
        case edit(CustomWord)
    }

    /// 下書きの結果
    enum DraftOutcome {
        /// この内容で作る
        case draft(GroupEditor.WordDraft)
        /// 作らずに単語帳の語（同じ綴りの同梱語）を選ぶ
        case bundled(wordId: String)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var word = ""
    /// 意味の欄。消したり足したりしても入力中の欄がずれないよう、意味ごとに ID を持たせる
    @State private var senses: [SenseField] = [SenseField(sense: WordSense(pos: .noun, meaning: ""))]
    /// 1 つ目の意味の品詞を自分で選んだか。選ぶまでは英語の入力から自動で推測する
    @State private var posTouched = false
    @FocusState private var focusedField: Field?

    private struct SenseField: Identifiable, Equatable {
        let id = UUID()
        var sense: WordSense
    }

    private enum Field: Hashable {
        case word
        case meaning(UUID)
        case example(UUID)
        case exampleJa(UUID)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// 下書きのときの、結果を返すコールバック
    private var onDone: ((DraftOutcome) -> Void)? {
        if case .draft(_, _, let onDone) = mode { return onDone }
        return nil
    }

    private var draft: GroupEditor.WordDraft {
        var value = GroupEditor.WordDraft(word: word)
        value.senses = senses.map(\.sense)
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("英語（例: take care of）", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .word)
                        .submitLabel(.next)
                        .onSubmit { focusedField = senses.first.map { .meaning($0.id) } }
                } header: {
                    Text("英語")
                } footer: {
                    duplicateHint
                }

                ForEach(Array(senses.enumerated()), id: \.element.id) { index, field in
                    senseSection(field, index: index)
                }

                Section {
                    Button {
                        addSense()
                    } label: {
                        Label("意味を追加", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("品詞の違う意味（commute の「動詞: 通勤する」「名詞: 通勤」など）は、1 つの単語にまとめられます。")
                }
            }
            .navigationTitle(isEditing ? "単語を編集" : "単語を作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "完了") { save() }
                        .disabled(!draft.isValid)
                }
            }
        }
        .onAppear {
            switch mode {
            case .edit(let custom):
                load(custom.draft)
                posTouched = true
            case .draft(let prefill, let posConfirmed, _):
                load(prefill)
                posTouched = posConfirmed
                // 英語が入っていれば次は意味、意味だけなら英語を入れてもらう
                if prefill.trimmed.meaning.isEmpty || prefill.trimmed.word.isEmpty {
                    focusedField = prefill.trimmed.word.isEmpty ? .word : senses.first.map { .meaning($0.id) }
                }
            }
        }
        .onChange(of: word) { _, word in
            if !posTouched, !senses.isEmpty {
                senses[0].sense.pos = GroupEditor.WordDraft.guessedPos(for: word)
            }
        }
    }

    // MARK: - 意味 1 つ分

    private func senseSection(_ field: SenseField, index: Int) -> some View {
        Section {
            TextField("意味（例: 〜の世話をする）", text: binding(field.id, \.meaning))
                .focused($focusedField, equals: .meaning(field.id))
                .submitLabel(.next)
                .onSubmit { focusedField = .example(field.id) }
            Picker("品詞", selection: posBinding(field.id)) {
                ForEach(PartOfSpeech.allCases, id: \.self) { pos in
                    Text(pos.label).tag(pos)
                }
            }
            TextField("例文（英語・任意）", text: binding(field.id, \.example), axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .example(field.id))
            TextField("例文の訳（任意）", text: binding(field.id, \.exampleJa), axis: .vertical)
                .focused($focusedField, equals: .exampleJa(field.id))
            if senses.count > 1 {
                Button(role: .destructive) {
                    removeSense(field.id)
                } label: {
                    Label("この意味を消す", systemImage: "minus.circle")
                }
            }
        } header: {
            Text(senses.count > 1 ? "意味 \(index + 1)" : "意味")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if index == 0 {
                    posHint
                }
                exampleHint(field.sense)
            }
        }
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<WordSense, String>) -> Binding<String> {
        Binding(
            get: { senses.first { $0.id == id }?.sense[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = senses.firstIndex(where: { $0.id == id }) else { return }
                senses[index].sense[keyPath: keyPath] = value
            }
        )
    }

    private func posBinding(_ id: UUID) -> Binding<PartOfSpeech> {
        Binding(
            get: { senses.first { $0.id == id }?.sense.pos ?? .noun },
            set: { value in
                guard let current = senses.firstIndex(where: { $0.id == id }) else { return }
                senses[current].sense.pos = value
                if current == 0 { posTouched = true }
            }
        )
    }

    private func addSense() {
        let field = SenseField(sense: WordSense(pos: draft.nextSensePos, meaning: ""))
        senses.append(field)
        focusedField = .meaning(field.id)
    }

    private func removeSense(_ id: UUID) {
        guard senses.count > 1 else { return }
        focusedField = nil
        senses.removeAll { $0.id == id }
    }

    private func load(_ value: GroupEditor.WordDraft) {
        word = value.word
        senses = value.senses.map { SenseField(sense: $0) }
    }

    // MARK: - 案内

    /// 品詞が自動で決めたままなら見直しを促す（名詞のまま動詞を登録すると、
    /// 誤答肢が名詞ばかりになり、穴埋めでは文法だけで答えが分かってしまう）
    @ViewBuilder
    private var posHint: some View {
        if !posTouched, !draft.trimmed.word.isEmpty, let first = senses.first {
            Text("品詞は自動で「\(first.sense.pos.label)」にしています。違うときは選び直してください。選択肢は同じ品詞の語から選ばれます。")
        }
    }

    /// 例文に単語が見つからないときは、穴埋め問題にならないことを伝える
    @ViewBuilder
    private func exampleHint(_ sense: WordSense) -> some View {
        if draft.exampleMissesWord(in: sense) {
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
        if !isEditing, let bundled = store.bundledWord(spelledLike: word) {
            VStack(alignment: .leading, spacing: 6) {
                Text("「\(bundled.word)」（\(bundled.meaning)）は単語帳にあります。")
                if let onDone {
                    Button("単語帳の「\(bundled.word)」を選ぶ") {
                        onDone(.bundled(wordId: bundled.id))
                        dismiss()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func save() {
        switch mode {
        case .draft(_, _, let onDone):
            onDone(.draft(draft.trimmed))
        case .edit(let custom):
            GroupEditor(context: context).update(custom, with: draft)
        }
        dismiss()
    }
}
