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
}
