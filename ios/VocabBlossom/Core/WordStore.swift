import Foundation

/// 同梱デッキの読み込みと索引。
///
/// 単語データは SwiftData に入れず、起動時に JSON をデコードしてメモリ上に持つ
/// （2,443 件・約 600KB。検索も線形で足りる）。
final class WordStore {
    /// アプリ全体で共有する索引。初回アクセス時に一度だけ読み込む。
    static let shared = WordStore.loadFromBundle()

    /// バンドル内の並び順。ID の連番順でもあるので、この順を一覧表示にも使う。
    static let deckFileNames = ["a1-1", "a1-2", "a2-1", "a2-2", "phrases"]
    /// フォルダ参照でバンドルへ同梱しているサブディレクトリ名（`data/decks`）
    static let bundleSubdirectory = "decks"

    let decks: [Deck]
    let allWords: [WordEntry]

    private let byId: [String: WordEntry]
    private let deckIdByWordId: [String: String]
    private let wordsByLevel: [CefrLevel: [WordEntry]]

    init(decks: [Deck]) {
        self.decks = decks
        let words = decks.flatMap(\.words)
        allWords = words
        byId = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        deckIdByWordId = Dictionary(
            decks.flatMap { deck in deck.words.map { ($0.id, deck.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        wordsByLevel = Dictionary(grouping: words, by: \.level)
    }

    /// アプリバンドルから全デッキを読み込む。データ不備は起動時に落として気付けるようにする。
    static func loadFromBundle(_ bundle: Bundle = .main) -> WordStore {
        let decoder = JSONDecoder()
        let decks = deckFileNames.map { name -> Deck in
            guard let url = bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: bundleSubdirectory
            ) else {
                fatalError("デッキ \(name).json がバンドルに見つかりません")
            }
            do {
                return try decoder.decode(Deck.self, from: Data(contentsOf: url))
            } catch {
                fatalError("デッキ \(name).json のデコードに失敗しました: \(error)")
            }
        }
        return WordStore(decks: decks)
    }

    func word(id: String) -> WordEntry? { byId[id] }

    func deck(of wordId: String) -> Deck? {
        guard let deckId = deckIdByWordId[wordId] else { return nil }
        return decks.first { $0.id == deckId }
    }

    func words(level: CefrLevel) -> [WordEntry] { wordsByLevel[level] ?? [] }

    /// 単語・意味・例文の部分一致検索（大小文字無視）。
    func search(_ query: String) -> [WordEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allWords }
        return allWords.filter {
            $0.word.localizedCaseInsensitiveContains(trimmed)
                || $0.meaning.localizedCaseInsensitiveContains(trimmed)
                || $0.example.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
