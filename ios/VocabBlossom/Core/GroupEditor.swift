import Foundation
import SwiftData

extension Notification.Name {
    /// グループ・自作語を変えて保存した。`SyncService` が少し待ってから同期する
    static let syncableDataDidChange = Notification.Name("syncableDataDidChange")
}

/// グループと自作語の読み書き。`LearningEngine` と同じく SwiftData に触る処理をここへ集める。
///
/// 書き込みは `updatedAt` を進める（同期で送る差分はそれで見分ける）。削除は削除記録（`SyncDeletion`）を残す。
struct GroupEditor {
    let context: ModelContext

    // MARK: - グループ

    @discardableResult
    func createGroup(name: String, now: Date = .now) -> WordGroup {
        let group = WordGroup(name: Self.normalizedName(name), createdAt: now, updatedAt: now)
        context.insert(group)
        save()
        return group
    }

    func rename(_ group: WordGroup, to name: String, now: Date = .now) {
        group.name = Self.normalizedName(name)
        group.updatedAt = now
        save()
    }

    /// グループだけを消す。中の単語・進捗・自作語は残す
    func delete(_ group: WordGroup, now: Date = .now) {
        recordDeletion(.group, id: group.id.syncId, at: now)
        GroupAnswerLog.purge(groupId: group.id, in: context)
        context.delete(group)
        save()
    }

    /// 末尾に追加する。すでに入っている語は飛ばす（順番も動かさない）
    func add(wordIds: [String], to group: WordGroup, now: Date = .now) {
        var seen = Set(group.wordIds)
        let additions = wordIds.filter { seen.insert($0).inserted }
        guard !additions.isEmpty else { return }
        group.wordIds.append(contentsOf: additions)
        group.updatedAt = now
        save()
    }

    func remove(wordIds: [String], from group: WordGroup, now: Date = .now) {
        let targets = Set(wordIds)
        guard group.wordIds.contains(where: targets.contains) else { return }
        group.wordIds.removeAll { targets.contains($0) }
        group.updatedAt = now
        save()
    }

    /// 選択画面の結果をまとめて反映する。外した語は消し、新しく選んだ語は選んだ順で末尾に足す
    func setMembership(_ selectedIds: [String], for group: WordGroup, now: Date = .now) {
        let selected = Set(selectedIds)
        var next = group.wordIds.filter { selected.contains($0) }
        var seen = Set(next)
        next.append(contentsOf: selectedIds.filter { seen.insert($0).inserted })
        guard next != group.wordIds else { return }
        group.wordIds = next
        group.updatedAt = now
        save()
    }

    static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新しいグループ" : trimmed
    }

    // MARK: - 自作語

    struct WordDraft: Equatable {
        var word = ""
        /// `meaning`・`pos`・`example`・`exampleJa` は 1 つ目の意味。2 つ目以降は `extraSenses`
        var meaning = ""
        var pos: PartOfSpeech = .noun
        var example = ""
        var exampleJa = ""
        /// 2 つ目以降の意味（品詞の違う意味）
        var extraSenses: [WordSense] = []

        /// 1 つ目の意味
        var primarySense: WordSense {
            get { WordSense(pos: pos, meaning: meaning, example: example, exampleJa: exampleJa) }
            set {
                pos = newValue.pos
                meaning = newValue.meaning
                example = newValue.example
                exampleJa = newValue.exampleJa
            }
        }

        /// すべての意味（1 つ目 + 2 つ目以降）。空の配列を入れたときは 1 つ目を空の意味にする
        var senses: [WordSense] {
            get { [primarySense] + extraSenses }
            set {
                primarySense = newValue.first ?? WordSense(pos: pos, meaning: "")
                extraSenses = Array(newValue.dropFirst())
            }
        }

        /// 英語と、すべての意味の「意味」が入っていれば保存できる
        var isValid: Bool {
            let value = trimmed
            return !value.word.isEmpty && value.senses.allSatisfy { !$0.meaning.isEmpty }
        }

        var trimmed: WordDraft {
            var value = WordDraft(word: word.trimmingCharacters(in: .whitespacesAndNewlines))
            value.senses = senses.map { sense in
                WordSense(
                    pos: sense.pos,
                    meaning: sense.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                    example: sense.example.trimmingCharacters(in: .whitespacesAndNewlines),
                    exampleJa: sense.exampleJa.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return value
        }

        /// 1 つ目の意味の例文は入っているのに、その中に英語（活用形を含む）が見つからない
        var exampleMissesWord: Bool { exampleMissesWord(in: primarySense) }

        /// 例文は入っているのに、その中に英語（活用形を含む）が見つからない。
        /// このときは穴埋め問題にならない（英→日などにフォールバックする）
        func exampleMissesWord(in sense: WordSense) -> Bool {
            let headword = word.trimmingCharacters(in: .whitespacesAndNewlines)
            let example = sense.example.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headword.isEmpty, !example.isEmpty else { return false }
            return Inflector.findHeadword(in: example, headword: headword) == nil
        }

        /// 意味を足すときの品詞。まだ使っていない品詞（名詞 → 動詞 → 形容詞 → 副詞の順）にする
        var nextSensePos: PartOfSpeech {
            let used = Set(senses.map(\.pos))
            return [PartOfSpeech.noun, .verb, .adjective, .adverb].first { !used.contains($0) } ?? .noun
        }

        /// 単語帳の検索語から作る下書き。英語（ASCII だけ）なら英語欄に、日本語などなら意味欄に入れる
        static func prefilled(fromSearch query: String) -> WordDraft {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return WordDraft() }
            guard text.unicodeScalars.allSatisfy(\.isASCII) else { return WordDraft(meaning: text) }
            return WordDraft(word: text, pos: guessedPos(for: text))
        }

        /// 空白を含む英語は熟語とみなす（品詞を選ぶ前の初期値）
        static func guessedPos(for word: String) -> PartOfSpeech {
            word.trimmingCharacters(in: .whitespacesAndNewlines).contains(" ") ? .phrase : .noun
        }
    }

    /// 自作語を作る。`group` を渡すとそのグループの末尾にも入れる
    @discardableResult
    func createCustomWord(
        _ draft: WordDraft,
        addingTo group: WordGroup? = nil,
        now: Date = .now
    ) -> CustomWord {
        let value = draft.trimmed
        let custom = CustomWord(
            word: value.word,
            meaning: value.meaning,
            pos: value.pos,
            example: value.example,
            exampleJa: value.exampleJa,
            extraSenses: value.extraSenses,
            createdAt: now,
            updatedAt: now
        )
        context.insert(custom)
        if let group {
            group.wordIds.append(custom.wordId)
            group.updatedAt = now
        }
        save()
        return custom
    }

    /// 「単語を追加」で新しく作る語を保存する。同じ綴りのマイ単語は 1 つだけにする。
    ///
    /// 同じ綴り（大小文字・前後の空白は無視）のマイ単語が無ければ作る。あればいちばん新しく更新したものの内容を置き換え
    /// （ID はそのままなので学習の記録は残る）、ほかの同じ綴りのマイ単語は、グループでの位置を寄せる先に引き継いでから消す
    @discardableResult
    func upsertCustomWord(_ draft: WordDraft, now: Date = .now) -> CustomWord {
        let spelling = WordStore.normalizedSpelling(draft.word)
        let sameSpelling = ((try? context.fetch(FetchDescriptor<CustomWord>())) ?? [])
            .filter { WordStore.normalizedSpelling($0.word) == spelling }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let kept = sameSpelling.first else { return createCustomWord(draft, now: now) }
        for duplicate in sameSpelling.dropFirst() {
            mergeIntoGroups(duplicate.wordId, keeping: kept.wordId, now: now)
            deleteCustomWord(id: duplicate.wordId, now: now)
        }
        update(kept, with: draft, now: now)
        return kept
    }

    /// グループの中の `wordId` を `keptId` に置き換える（すでに `keptId` があるグループでは外すだけ）
    private func mergeIntoGroups(_ wordId: String, keeping keptId: String, now: Date) {
        let groups = (try? context.fetch(FetchDescriptor<WordGroup>())) ?? []
        for group in groups where group.wordIds.contains(wordId) {
            if group.wordIds.contains(keptId) {
                group.wordIds.removeAll { $0 == wordId }
            } else {
                group.wordIds = group.wordIds.map { $0 == wordId ? keptId : $0 }
            }
            group.updatedAt = max(group.updatedAt, now)
        }
    }

    func update(_ custom: CustomWord, with draft: WordDraft, now: Date = .now) {
        let value = draft.trimmed
        custom.word = value.word
        custom.meaning = value.meaning
        custom.pos = value.pos
        custom.example = value.example
        custom.exampleJa = value.exampleJa
        custom.extraSenses = value.extraSenses
        custom.updatedAt = now
        save()
    }

    func customWord(id wordId: String) -> CustomWord? {
        var descriptor = FetchDescriptor<CustomWord>(
            predicate: #Predicate { $0.wordId == wordId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 自作語を消す。解決できない ID を残さないよう、グループ・進捗・回答ログからも消す。
    /// 外したグループの `updatedAt` も進める（サーバーも同じように進めるので、同期でぶつかってもそろう）
    func deleteCustomWord(id wordId: String, now: Date = .now) {
        recordDeletion(.customWord, id: wordId, at: now)
        Self.purgeCustomWord(id: wordId, in: context, groupsUpdatedAt: now)
        save()
    }

    /// 自作語とその痕跡（グループの中の ID・進捗・回答ログ・グループの回答の記録）を消す。削除記録は作らない（同期で届いた削除にも使う）
    ///
    /// - Parameter groupsUpdatedAt: 外したグループの `updatedAt` をここまで進める。nil なら変えない
    static func purgeCustomWord(id wordId: String, in context: ModelContext, groupsUpdatedAt: Date?) {
        var descriptor = FetchDescriptor<CustomWord>(predicate: #Predicate { $0.wordId == wordId })
        descriptor.fetchLimit = 1
        if let custom = (try? context.fetch(descriptor))?.first {
            context.delete(custom)
        }
        let groups = (try? context.fetch(FetchDescriptor<WordGroup>())) ?? []
        for group in groups where group.wordIds.contains(wordId) {
            group.wordIds.removeAll { $0 == wordId }
            if let groupsUpdatedAt, groupsUpdatedAt > group.updatedAt {
                group.updatedAt = groupsUpdatedAt
            }
        }
        try? context.delete(model: WordProgress.self, where: #Predicate { $0.wordId == wordId })
        try? context.delete(model: AnswerLog.self, where: #Predicate { $0.wordId == wordId })
        try? context.delete(model: GroupAnswerLog.self, where: #Predicate { $0.wordId == wordId })
    }

    private func recordDeletion(_ kind: SyncKind, id recordId: String, at now: Date) {
        let existing = (try? context.fetch(FetchDescriptor<SyncDeletion>(
            predicate: #Predicate { $0.recordId == recordId }
        ))) ?? []
        if let deletion = existing.first(where: { $0.kind == kind }) {
            deletion.deletedAt = max(deletion.deletedAt, now)
        } else {
            context.insert(SyncDeletion(kind: kind, recordId: recordId, deletedAt: now))
        }
    }

    private func save() {
        do {
            try context.save()
            NotificationCenter.default.post(name: .syncableDataDidChange, object: nil)
        } catch {
            assertionFailure("グループの保存に失敗しました: \(error)")
        }
    }
}

extension CustomWord {
    var draft: GroupEditor.WordDraft {
        GroupEditor.WordDraft(
            word: word, meaning: meaning, pos: pos, example: example, exampleJa: exampleJa,
            extraSenses: extraSenses
        )
    }
}
