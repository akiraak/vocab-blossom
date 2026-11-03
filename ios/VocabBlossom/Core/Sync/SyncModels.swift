import Foundation
import SwiftData

/// 同期する削除の種類。サーバーの `kind`（`group` / `customWord`）と同じ文字列
nonisolated enum SyncKind: String, Codable, Sendable {
    case group
    case customWord
}

/// まだサーバーへ送っていない削除の記録（tombstone）。
///
/// `GroupEditor` がグループ・自作語を消したときに作り、同期でサーバーの状態が返ってきたら消す。
@Model
final class SyncDeletion {
    var kind: SyncKind
    /// グループは UUID の小文字、自作語は `custom-…`
    var recordId: String
    var deletedAt: Date

    init(kind: SyncKind, recordId: String, deletedAt: Date) {
        self.kind = kind
        self.recordId = recordId
        self.deletedAt = deletedAt
    }
}

nonisolated extension Date {
    /// 同期で使うミリ秒の整数（UNIX エポック）。比較もこの値で行い、端数の差で食い違わないようにする
    var syncMillis: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    init(syncMillis: Int64) {
        self.init(timeIntervalSince1970: Double(syncMillis) / 1000)
    }
}

nonisolated extension UUID {
    /// サーバーは UUID を小文字で持つ（Swift の `uuidString` は大文字）
    var syncId: String { uuidString.lowercased() }
}

/// `POST /api/sync` の型。日時はミリ秒の整数で送受信する（docs/plans/archive/admin-server.md の Phase 2）
nonisolated enum SyncAPI {
    struct Group: Codable, Equatable, Sendable {
        var id: String
        var name: String
        var wordIds: [String]
        var createdAt: Date
        var updatedAt: Date
    }

    struct CustomWord: Codable, Equatable, Sendable {
        var wordId: String
        var word: String
        var meaning: String
        var pos: PartOfSpeech
        var example: String
        var exampleJa: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct Deletion: Codable, Equatable, Sendable {
        var kind: SyncKind
        var id: String
        var deletedAt: Date
    }

    struct Request: Codable, Equatable, Sendable {
        var cursor: Int
        var groups: [Group]
        var customWords: [CustomWord]
        var deletions: [Deletion]
    }

    struct Response: Codable, Equatable, Sendable {
        var cursor: Int
        var reset: Bool
        var groups: [Group]
        var customWords: [CustomWord]
        var deletions: [Deletion]
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.syncMillis)
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(syncMillis: try container.decode(Int64.self))
        }
        return decoder
    }
}
