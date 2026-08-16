import Foundation

/// 単語の並びを ABC 順から崩すための、結果が毎回同じになるシャッフル。
///
/// 呼ぶたびにランダムだと、ホームに出した「今日の学習」とセッションの中身がずれたり、
/// 中断して開き直すたびに残りの新規語が入れ替わったりする。
/// 並び順を「単語 ID と種から決まる値」にすることで、
/// 「ABC 順ではない」と「同じ端末なら何度並べても同じ」を両立させる。
struct ShuffleOrder {
    enum Key {
        static let seed = "shuffle.seed"
    }

    /// 端末ごとの種。初回に一度だけ作って保存するので、アプリを入れ直すまで並びは変わらない
    static let install = ShuffleOrder(storedIn: .standard)

    let seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
    }

    init(storedIn defaults: UserDefaults) {
        if let stored = defaults.object(forKey: Key.seed) as? Int {
            seed = UInt64(bitPattern: Int64(stored))
        } else {
            seed = UInt64.random(in: UInt64.min...UInt64.max)
            defaults.set(Int(Int64(bitPattern: seed)), forKey: Key.seed)
        }
    }

    /// 並び替えのキー。`Hashable` の `hashValue` はプロセスごとに変わるので使わず、
    /// FNV-1a で自前にハッシュして種と混ぜる。
    func key(_ id: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return Self.mix(hash ^ seed)
    }

    /// ID をもとに並べ替える。キーが同着（まず起きない）のときは ID 順で安定させる
    func shuffled<T>(_ items: [T], id: (T) -> String) -> [T] {
        let keyed: [(key: UInt64, id: String, value: T)] = items.map { item in
            let itemId = id(item)
            return (key: key(itemId), id: itemId, value: item)
        }
        let sorted = keyed.sorted { left, right in
            left.key == right.key ? left.id < right.id : left.key < right.key
        }
        return sorted.map(\.value)
    }

    func shuffled(_ ids: [String]) -> [String] {
        shuffled(ids) { $0 }
    }

    /// splitmix64 の撹拌。ハッシュの偏りをならして、隣り合う ID が近い順に並ばないようにする
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
