import Foundation

/// 穴埋め用の文章 1 パターン。`text` の見出し語を空欄にして出し、答えたあと `ja` を見せる。
///
/// 文章はサーバー（`POST /api/passages`）が AI で作り、端末の `PassageCache` にためる。設計は docs/plans/fill-blank-passages.md
nonisolated struct Passage: Codable, Equatable, Hashable, Sendable {
    var text: String
    var ja: String
}

/// 語と意味から、その意味の文章を引く。テストや文章を使わない場面では `PassageLookup.none`
typealias PassageLookup = @Sendable (WordEntry, WordSense) -> [Passage]

nonisolated enum Passages {
    static let none: PassageLookup = { _, _ in [] }

    /// 文章の鍵。サーバーと同じく「綴り（小文字）・品詞・意味」。意味を直したマイ単語は別の鍵になり、作り直す
    static func key(word: String, sense: WordSense) -> String {
        [
            word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            sense.pos.rawValue,
            sense.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: "\t")
    }
}

/// 端末にためた文章。Application Support の JSON 1 ファイルに「鍵 → 3 パターン」で持つ。
///
/// 消えてもサーバーから取り直せるので、同期・バックアップには入れない
nonisolated final class PassageCache: @unchecked Sendable {
    static let shared = PassageCache(fileURL: PassageCache.defaultFileURL)

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "passages.json")
    }

    private let fileURL: URL?
    private let lock = NSLock()
    private var entries: [String: [Passage]]

    /// `fileURL` が nil なら保存しない（テスト用）
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: [Passage]].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func passages(word: String, sense: WordSense) -> [Passage] {
        lock.withLock { entries[Passages.key(word: word, sense: sense)] ?? [] }
    }

    func contains(word: String, sense: WordSense) -> Bool {
        !passages(word: word, sense: sense).isEmpty
    }

    /// 鍵ごとの文章を足して保存する（空の文章は入れない）
    func store(_ passages: [String: [Passage]]) {
        let snapshot: [String: [Passage]] = lock.withLock {
            for (key, value) in passages where !value.isEmpty {
                entries[key] = value
            }
            return entries
        }
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var lookup: PassageLookup {
        { [self] word, sense in passages(word: word.word, sense: sense) }
    }
}
