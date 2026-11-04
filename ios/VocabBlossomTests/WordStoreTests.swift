import Foundation
import Testing

@testable import VocabBlossom

@Suite("単語データの読み込み")
struct WordStoreTests {
    let store = WordStore.shared

    @Test("バンドル同梱の 5 デッキを読み込める")
    func loadsAllDecks() {
        #expect(store.decks.count == WordStore.deckFileNames.count)
        #expect(store.decks.allSatisfy { !$0.words.isEmpty })
        #expect(store.allWords.count == 2443)
    }

    @Test("ID で単語を引ける")
    func lookupById() throws {
        let word = try #require(store.word(id: "a1-0001"))
        #expect(word.word == "a.m.")
        #expect(word.level == .a1)
        #expect(store.word(id: "nope") == nil)
    }

    @Test("単語からデッキを引ける")
    func deckOfWord() throws {
        #expect(store.deck(of: "a1-0001")?.id == "a1-1")
        #expect(store.deck(of: "ph-0001")?.id == "phrases")
    }

    @Test("レベル別に絞り込める")
    func wordsByLevel() {
        let a1 = store.words(level: .a1)
        let a2 = store.words(level: .a2)
        #expect(a1.allSatisfy { $0.level == .a1 })
        #expect(a2.allSatisfy { $0.level == .a2 })
        #expect(a1.count + a2.count == store.allWords.count)
    }

    @Test("新規学習プールはレベル内をシャッフルした並び")
    func newWordPoolIsShuffled() {
        let words = store.words(level: .a1)
        let pool = store.newWordPool(level: .a1, order: .test)

        #expect(Set(pool.map(\.id)) == Set(words.map(\.id)))
        #expect(pool.count == words.count)
        // デッキは ABC 順（＝ ID 順）なので、そのままの並びになっていないこと
        #expect(pool.map(\.id) != words.map(\.id))
        // 熟語デッキは ID が後ろに固まるが、シャッフルすれば序盤から混ざる
        #expect(pool.prefix(50).contains { $0.pos == .phrase })
    }

    @Test("同じ並びを指定すれば新規学習プールの順番は変わらない")
    func newWordPoolIsStable() {
        #expect(
            store.newWordPool(level: .a2, order: .test).map(\.id)
                == store.newWordPool(level: .a2, order: .test).map(\.id)
        )
    }

    @Test("同梱語は意味が 1 つ（データに extraSenses が無くても読める）")
    func bundledWordsHaveOneSense() throws {
        #expect(store.allWords.allSatisfy { $0.extraSenses.isEmpty })
        let apple = try #require(store.search("apple").first)
        #expect(apple.senses == [apple.primarySense])
    }

    @Test("単語・意味・例文を横断して検索できる")
    func search() {
        #expect(store.search("apple").contains { $0.word == "apple" })
        #expect(store.search("  ").count == store.allWords.count)
    }

    @Test("検索語に近い語を上に出す（同梱語の home は例文に home を含む語より前）")
    func searchPutsHeadwordFirst() {
        #expect(store.search("home").first?.word == "home")
        #expect(store.search(" Home ").first?.word == "home")
    }

    @Test("大文字小文字は区別しない（英語・意味・例文とも、並びも同じ）")
    func searchIgnoresCase() {
        let lower = store.search("home").map(\.id)
        #expect(!lower.isEmpty)
        #expect(store.search("Home").map(\.id) == lower)
        #expect(store.search("HOME").map(\.id) == lower)
        // 例文だけに出てくる語も大小文字を無視して見つかる（例文の文頭は大文字）
        #expect(store.search("i").count == store.search("I").count)
    }

    @Test("完全一致 → 前方一致 → 英語の部分一致 → 意味 → 例文の順。同じ順位の中は元の並び")
    func filterRanking() {
        func entry(_ id: String, _ word: String, meaning: String = "意味", example: String = "") -> WordEntry {
            WordEntry(
                id: id, word: word, pos: .noun, level: .a1,
                meaning: meaning, example: example, exampleJa: ""
            )
        }
        let words = [
            entry("example", "door", example: "I came home late."),
            entry("meaning", "house", meaning: "家（home）"),
            entry("contains", "at home", meaning: "家で"),
            entry("prefix2", "homework", meaning: "宿題"),
            entry("exact", "Home", meaning: "家"),
            entry("prefix1", "homeroom", meaning: "ホームルーム"),
            entry("none", "school", meaning: "学校"),
        ]
        #expect(WordStore.filter(words, query: "home").map(\.id)
            == ["exact", "prefix2", "prefix1", "contains", "meaning", "example"])
        #expect(WordStore.filter(words, query: "").map(\.id) == words.map(\.id))
    }
}
