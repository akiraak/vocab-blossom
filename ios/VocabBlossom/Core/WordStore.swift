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
    /// ユーザーの自作語（作成順）。デッキ・レベル別プールには含めない
    let customWords: [WordEntry]
    /// 同梱語 → 自作語 の順
    let allWords: [WordEntry]

    private let byId: [String: WordEntry]
    private let customById: [String: WordEntry]
    private let deckIdByWordId: [String: String]
    private let wordsByLevel: [CefrLevel: [WordEntry]]

    init(decks: [Deck], customWords: [WordEntry] = []) {
        self.decks = decks
        let words = decks.flatMap(\.words)
        byId = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        deckIdByWordId = Dictionary(
            decks.flatMap { deck in deck.words.map { ($0.id, deck.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        wordsByLevel = Dictionary(
            grouping: words.filter { $0.level != nil },
            by: { $0.level ?? .a1 }
        )
        self.customWords = customWords
        customById = Dictionary(
            customWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        allWords = words + customWords
    }

    /// 同梱語の索引を使い回し、自作語を重ねた索引を作る（画面の再描画ごとに呼んでも軽いように）
    private init(base: WordStore, customWords: [WordEntry]) {
        decks = base.decks
        byId = base.byId
        deckIdByWordId = base.deckIdByWordId
        wordsByLevel = base.wordsByLevel
        self.customWords = customWords
        customById = Dictionary(
            customWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let bundled = base.allWords.prefix(base.allWords.count - base.customWords.count)
        allWords = Array(bundled) + customWords
    }

    /// 自作語を差し替えた索引。同梱語の部分はそのまま
    func including(customWords: [WordEntry]) -> WordStore {
        WordStore(base: self, customWords: customWords)
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

    func word(id: String) -> WordEntry? { byId[id] ?? customById[id] }

    /// ID の並びを単語に引き直す。見つからない ID（削除済みの自作語など）は飛ばす
    func words(ids: [String]) -> [WordEntry] { ids.compactMap(word(id:)) }

    func deck(of wordId: String) -> Deck? {
        guard let deckId = deckIdByWordId[wordId] else { return nil }
        return decks.first { $0.id == deckId }
    }

    func words(level: CefrLevel) -> [WordEntry] { wordsByLevel[level] ?? [] }

    /// 新規学習で出す順番。
    ///
    /// デッキの並びは CEFR-J の ABC 順（＝ ID 順）なので、そのまま出すと毎日 a から順に進む
    /// ことになる。レベル内をまるごとシャッフルして、単語も熟語も満遍なく出会えるようにする。
    func newWordPool(level: CefrLevel, order: ShuffleOrder = .install) -> [WordEntry] {
        order.shuffled(words(level: level), id: \.id)
    }

    /// 単語・意味・例文の部分一致検索（大小文字無視）。
    func search(_ query: String) -> [WordEntry] {
        Self.filter(allWords, query: query)
    }

    /// 単語・意味・例文の部分一致で絞り込む。空の検索語なら全件
    static func filter(_ words: [WordEntry], query: String) -> [WordEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return words }
        return words.filter {
            $0.word.localizedCaseInsensitiveContains(trimmed)
                || $0.meaning.localizedCaseInsensitiveContains(trimmed)
                || $0.example.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// 綴りが同じ同梱語（大小文字・前後の空白は無視）。自作語の重複登録の案内に使う
    func bundledWord(spelledLike text: String) -> WordEntry? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return allWords.first { !$0.isCustom && $0.word.lowercased() == normalized }
    }
}
