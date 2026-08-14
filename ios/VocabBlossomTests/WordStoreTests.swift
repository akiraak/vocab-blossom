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

    @Test("単語・意味・例文を横断して検索できる")
    func search() {
        #expect(store.search("apple").contains { $0.word == "apple" })
        #expect(store.search("  ").count == store.allWords.count)
    }
}
