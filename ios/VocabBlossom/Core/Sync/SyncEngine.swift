import Foundation
import SwiftData

/// 同期の中身（通信しない部分）。送る差分を組み立て、サーバーから返ってきた変更を SwiftData に当てる。
///
/// 規則はサーバーと同じ（docs/plans/archive/admin-server.md の Phase 2 / Phase 5）
/// - 送るのは `syncedUpdatedAt` と `updatedAt` が食い違うグループ・自作語と、まだ送っていない削除記録
/// - 受け取ったレコードは、手元に無いか、手元より新しいときだけ当てる（手元の方が新しければ次の同期で送る）
/// - 手元にまだ送っていない削除記録があり、その方が新しければ受け取ったレコードは当てない
/// - 日時の比較はミリ秒の整数で行う
struct SyncEngine {
    let context: ModelContext

    // MARK: - 送る

    func makeRequest(cursor: Int) throws -> SyncAPI.Request {
        let groups = try context.fetch(
            FetchDescriptor<WordGroup>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let customWords = try context.fetch(
            FetchDescriptor<CustomWord>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let deletions = try context.fetch(
            FetchDescriptor<SyncDeletion>(sortBy: [SortDescriptor(\.deletedAt)])
        )
        return SyncAPI.Request(
            cursor: cursor,
            groups: groups.filter(\.needsSync).map {
                SyncAPI.Group(
                    id: $0.id.syncId, name: $0.name, wordIds: $0.wordIds,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            customWords: customWords.filter(\.needsSync).map {
                SyncAPI.CustomWord(
                    wordId: $0.wordId, word: $0.word, meaning: $0.meaning, pos: $0.pos,
                    example: $0.example, exampleJa: $0.exampleJa, extraSenses: $0.extraSenses,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            deletions: deletions.map {
                SyncAPI.Deletion(kind: $0.kind, id: $0.recordId, deletedAt: $0.deletedAt)
            }
        )
    }

    // MARK: - 受け取る

    /// サーバーの返事を当てる。`sent` はこの返事のもとになった送信内容（送り終えた削除記録を消すのに使う）
    func apply(_ response: SyncAPI.Response, sent: SyncAPI.Request) throws {
        try removeSentDeletions(sent.deletions)
        // 通信している間に消したものは、まだ送っていない削除記録として残っている
        let pending = try pendingDeletions()

        for incoming in response.customWords {
            applyCustomWord(incoming, pending: pending)
        }
        for incoming in response.groups {
            applyGroup(incoming, pending: pending)
        }
        for incoming in response.deletions {
            applyDeletion(incoming, pending: pending)
        }
        if response.reset {
            try markAllForResend()
        }
        try context.save()
    }

    /// 全件を未送信に戻す（サーバーの DB が作り直された・接続先が変わった・バックアップから復元した）
    func markAllForResend() throws {
        for group in try context.fetch(FetchDescriptor<WordGroup>()) {
            group.syncedUpdatedAt = nil
        }
        for custom in try context.fetch(FetchDescriptor<CustomWord>()) {
            custom.syncedUpdatedAt = nil
        }
    }

    // MARK: - 内部

    private struct DeletionKey: Hashable {
        let kind: SyncKind
        let id: String
    }

    private func removeSentDeletions(_ sent: [SyncAPI.Deletion]) throws {
        guard !sent.isEmpty else { return }
        let sentAt = Dictionary(
            sent.map { (DeletionKey(kind: $0.kind, id: $0.id), $0.deletedAt.syncMillis) },
            uniquingKeysWith: max
        )
        for deletion in try context.fetch(FetchDescriptor<SyncDeletion>()) {
            let key = DeletionKey(kind: deletion.kind, id: deletion.recordId)
            // 送ったあとにもう一度消し直していたら（deletedAt が進んでいたら）残す
            if let millis = sentAt[key], deletion.deletedAt.syncMillis <= millis {
                context.delete(deletion)
            }
        }
    }

    private func pendingDeletions() throws -> [DeletionKey: SyncDeletion] {
        let deletions = try context.fetch(FetchDescriptor<SyncDeletion>())
            .filter { !$0.isDeleted }
        return Dictionary(
            deletions.map { (DeletionKey(kind: $0.kind, id: $0.recordId), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// 手元の削除記録の方が新しい（または同時）なら、受け取ったレコードは当てない。古ければ削除記録を捨てる
    private func isBlocked(
        _ key: DeletionKey,
        updatedAt: Date,
        pending: [DeletionKey: SyncDeletion]
    ) -> Bool {
        guard let deletion = pending[key], !deletion.isDeleted else { return false }
        if deletion.deletedAt.syncMillis >= updatedAt.syncMillis { return true }
        context.delete(deletion)
        return false
    }

    private func applyCustomWord(_ incoming: SyncAPI.CustomWord, pending: [DeletionKey: SyncDeletion]) {
        let key = DeletionKey(kind: .customWord, id: incoming.wordId)
        guard !isBlocked(key, updatedAt: incoming.updatedAt, pending: pending) else { return }

        if let local = customWord(id: incoming.wordId) {
            if incoming.updatedAt.syncMillis > local.updatedAt.syncMillis {
                local.word = incoming.word
                local.meaning = incoming.meaning
                local.pos = incoming.pos
                local.example = incoming.example
                local.exampleJa = incoming.exampleJa
                local.extraSenses = incoming.extraSenses ?? []
                local.createdAt = incoming.createdAt
                local.updatedAt = incoming.updatedAt
            }
            local.syncedUpdatedAt = incoming.updatedAt
        } else {
            let custom = CustomWord(
                wordId: incoming.wordId,
                word: incoming.word,
                meaning: incoming.meaning,
                pos: incoming.pos,
                example: incoming.example,
                exampleJa: incoming.exampleJa,
                extraSenses: incoming.extraSenses ?? [],
                createdAt: incoming.createdAt,
                updatedAt: incoming.updatedAt
            )
            custom.syncedUpdatedAt = incoming.updatedAt
            context.insert(custom)
        }
    }

    private func applyGroup(_ incoming: SyncAPI.Group, pending: [DeletionKey: SyncDeletion]) {
        guard let id = UUID(uuidString: incoming.id) else { return }
        let key = DeletionKey(kind: .group, id: id.syncId)
        guard !isBlocked(key, updatedAt: incoming.updatedAt, pending: pending) else { return }

        // 手元で消してまだ送っていない自作語は入れない
        let wordIds = incoming.wordIds.filter { wordId in
            guard CustomWord.isCustom(wordId),
                  let deletion = pending[DeletionKey(kind: .customWord, id: wordId)]
            else { return true }
            return deletion.isDeleted
        }

        if let local = group(id: id) {
            if incoming.updatedAt.syncMillis > local.updatedAt.syncMillis {
                local.name = incoming.name
                local.wordIds = wordIds
                local.createdAt = incoming.createdAt
                local.updatedAt = incoming.updatedAt
            }
            local.syncedUpdatedAt = incoming.updatedAt
        } else {
            let group = WordGroup(
                id: id,
                name: incoming.name,
                wordIds: wordIds,
                createdAt: incoming.createdAt,
                updatedAt: incoming.updatedAt
            )
            group.syncedUpdatedAt = incoming.updatedAt
            context.insert(group)
        }
    }

    /// 削除を当てる。手元のレコードの方が新しければ（通信中に編集した）残して、次の同期で送る
    private func applyDeletion(_ incoming: SyncAPI.Deletion, pending: [DeletionKey: SyncDeletion]) {
        switch incoming.kind {
        case .group:
            guard let id = UUID(uuidString: incoming.id), let local = group(id: id) else { return }
            if local.updatedAt.syncMillis <= incoming.deletedAt.syncMillis {
                context.delete(local)
            }
        case .customWord:
            if let local = customWord(id: incoming.id),
               local.updatedAt.syncMillis > incoming.deletedAt.syncMillis {
                return
            }
            // グループはサーバーが外して updatedAt を進めたものが同じ返事で届くので、ここでは進めない
            GroupEditor.purgeCustomWord(id: incoming.id, in: context, groupsUpdatedAt: nil)
        }
    }

    private func group(id: UUID) -> WordGroup? {
        var descriptor = FetchDescriptor<WordGroup>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func customWord(id wordId: String) -> CustomWord? {
        var descriptor = FetchDescriptor<CustomWord>(predicate: #Predicate { $0.wordId == wordId })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
