import Foundation
import Testing

@testable import VocabBlossom

@Suite("結果が毎回同じシャッフル")
struct ShuffleOrderTests {
    /// ABC 順に並んだ ID
    let ids = (0..<200).map { String(format: "w-%04d", $0) }

    @Test("入力の順番から崩れる")
    func breaksTheOriginalOrder() {
        let shuffled = ShuffleOrder(seed: 1).shuffled(ids)
        #expect(shuffled != ids)
    }

    @Test("要素は過不足なく残る（並べ替えだけ）")
    func keepsEveryElement() {
        #expect(Set(ShuffleOrder(seed: 1).shuffled(ids)) == Set(ids))
        #expect(ShuffleOrder(seed: 1).shuffled(ids).count == ids.count)
    }

    @Test("同じ種なら何度でも同じ順、入力の順番にも左右されない")
    func sameSeedGivesSameOrder() {
        let order = ShuffleOrder(seed: 42)
        #expect(order.shuffled(ids) == order.shuffled(ids))
        #expect(order.shuffled(Array(ids.reversed())) == order.shuffled(ids))
        #expect(ShuffleOrder(seed: 42).shuffled(ids) == order.shuffled(ids))
    }

    @Test("種が違えば順番も違う")
    func differentSeedGivesDifferentOrder() {
        #expect(ShuffleOrder(seed: 1).shuffled(ids) != ShuffleOrder(seed: 2).shuffled(ids))
    }

    @Test("種は初回に作って保存し、次からは同じ値を使う")
    func seedIsGeneratedOnceAndStored() throws {
        let suiteName = "ShuffleOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ShuffleOrder(storedIn: defaults)
        #expect(defaults.object(forKey: ShuffleOrder.Key.seed) != nil)
        #expect(ShuffleOrder(storedIn: defaults).seed == first.seed)
    }
}
