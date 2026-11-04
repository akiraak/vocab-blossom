import Foundation
import Testing

@testable import VocabBlossom

@Suite("単語を追加（作成の導線）")
struct WordPickerTests {
    let store = WordStore.shared

    private func action(
        _ query: String, results: [WordEntry] = [], ai: Bool = true
    ) -> WordPicker.CreateAction? {
        WordPicker.createAction(query: query, results: results, assistAvailable: ai)
    }

    @Test("検索語が空（空白だけ）なら作成の導線を出さない")
    func noActionForEmptyQuery() {
        #expect(action("") == nil)
        #expect(action("  \n", results: store.allWords, ai: false) == nil)
    }

    @Test("見つからなくても、結果があっても出す（前後の空白は落とす）")
    func actionRegardlessOfResults() throws {
        let missing = try #require(action(" commute "))
        #expect(missing.text == "commute")
        #expect(missing.note == nil)

        let results = WordStore.filter(store.allWords, query: "tak")
        #expect(!results.isEmpty)
        let found = try #require(action("tak", results: results))
        #expect(found.text == "tak")
        #expect(found.note == nil)
    }

    @Test("AI が使えるかで文言が変わる")
    func titleDependsOnAssist() throws {
        let withAI = try #require(action("commute"))
        let withoutAI = try #require(action("commute", ai: false))
        #expect(withAI.title == "「commute」を AI で調べる")
        #expect(withoutAI.title == "「commute」を自分で作る")
    }

    @Test("同じ綴りの語が結果にあれば、そちらを選ぶよう補足する（大小文字は無視）")
    func noteWhenSameSpellingExists() throws {
        let results = WordStore.filter(store.allWords, query: "Take")
        #expect(results.contains { $0.word == "take" })
        let sameSpelling = try #require(action("Take", results: results))
        #expect(sameSpelling.note != nil)
    }
}
