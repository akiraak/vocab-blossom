import Foundation
import SwiftData

/// ユーザーが作る単語のグループ（マイ単語帳）。
///
/// 中身は単語 ID の並びだけを持つ。同梱語も自作語（`CustomWord`）も同じ ID で入り、
/// 進捗は単語ごとに共通なので、グループを消しても学習記録は残る。
@Model
final class WordGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    /// 追加した順。新規学習もこの順で出す
    var wordIds: [String]
    var createdAt: Date
    var updatedAt: Date
    /// サーバーと一致していると分かっている `updatedAt`。`updatedAt` と違えば次の同期で送る（nil は未送信）
    var syncedUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        wordIds: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.wordIds = wordIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 前回の同期のあとに手元で変わった
    var needsSync: Bool {
        syncedUpdatedAt?.syncMillis != updatedAt.syncMillis
    }

    /// 出題（誤答肢の選び方）に使う、すべてのグループの名前と単語 ID
    static func quizGroups(in context: ModelContext) -> [QuizGroup] {
        ((try? context.fetch(FetchDescriptor<WordGroup>())) ?? [])
            .map { QuizGroup(name: $0.name, wordIds: $0.wordIds) }
    }
}
