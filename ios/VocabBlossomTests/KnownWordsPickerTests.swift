import Foundation
import Testing

@testable import VocabBlossom

@Suite("既知語の一括登録")
struct KnownWordsPickerTests {
    let store = WordStore.shared

    @Test("対象は選択中レベルの未学習語だけ")
    func candidatesExcludeLearnedAndOtherLevels() {
        let pool = store.newWordPool(level: .a1)
        let learned = Set(pool.prefix(5).map(\.id))
        let candidates = KnownWordsPicker.candidates(
            store: store, level: .a1, learnedWordIds: learned
        )

        #expect(candidates.count == pool.count - 5)
        #expect(candidates.allSatisfy { $0.level == .a1 })
        #expect(!candidates.contains { learned.contains($0.id) })
    }

    @Test("並びは新規学習と同じ順（これから出会う順）")
    func candidatesKeepPoolOrder() {
        let pool = store.newWordPool(level: .a2)
        let candidates = KnownWordsPicker.candidates(
            store: store, level: .a2, learnedWordIds: []
        )
        #expect(candidates.map(\.id) == pool.map(\.id))
    }

    @Test("60 語ずつのページに区切られる")
    func pagesAreSixtyWords() {
        let candidates = KnownWordsPicker.candidates(
            store: store, level: .a1, learnedWordIds: []
        )
        let first = KnownWordsPicker.page(candidates, at: 0)
        let second = KnownWordsPicker.page(candidates, at: 1)

        #expect(first.count == KnownWordsPicker.pageSize)
        #expect(second.count == KnownWordsPicker.pageSize)
        #expect(first.map(\.id) == candidates.prefix(60).map(\.id))
        #expect(second.map(\.id) == candidates.dropFirst(60).prefix(60).map(\.id))
    }

    @Test("最後のページは端数になり、範囲外は空")
    func lastPageAndOutOfRange() {
        let candidates = KnownWordsPicker.candidates(
            store: store, level: .a1, learnedWordIds: []
        )
        let pageCount = KnownWordsPicker.pageCount(candidates)
        let last = KnownWordsPicker.page(candidates, at: pageCount - 1)

        #expect(!last.isEmpty)
        #expect(last.count <= KnownWordsPicker.pageSize)
        #expect(
            (pageCount - 1) * KnownWordsPicker.pageSize + last.count == candidates.count
        )
        #expect(KnownWordsPicker.page(candidates, at: pageCount).isEmpty)
    }

    @Test("全部学習済みなら対象は空で、ページも 0")
    func noCandidatesWhenEverythingIsLearned() {
        let pool = store.newWordPool(level: .a1)
        let candidates = KnownWordsPicker.candidates(
            store: store, level: .a1, learnedWordIds: Set(pool.map(\.id))
        )
        #expect(candidates.isEmpty)
        #expect(KnownWordsPicker.pageCount(candidates) == 0)
        #expect(KnownWordsPicker.page(candidates, at: 0).isEmpty)
    }
}
