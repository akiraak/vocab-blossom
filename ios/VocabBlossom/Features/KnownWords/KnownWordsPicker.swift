import Foundation

/// 「知っている語をまとめて選ぶ」画面の出題順と区切りを決める。
///
/// 画面から切り離しておくことで、対象の絞り込みとページ分割を単体テストできるようにする。
enum KnownWordsPicker {
    /// 1 画面に出す語数。テンポよく処理できて、進んでいる実感も残る粒度
    static let pageSize = 60

    /// 選択中レベルの未学習語を、新規学習と同じ順（＝これから出会う順）で返す。
    static func candidates(
        store: WordStore,
        level: CefrLevel,
        learnedWordIds: Set<String>
    ) -> [WordEntry] {
        store.newWordPool(level: level).filter { !learnedWordIds.contains($0.id) }
    }

    /// `pageSize` ごとに区切った 1 ページ分。範囲外なら空
    static func page(_ candidates: [WordEntry], at index: Int) -> [WordEntry] {
        let start = index * pageSize
        guard start < candidates.count else { return [] }
        return Array(candidates[start..<min(start + pageSize, candidates.count)])
    }

    static func pageCount(_ candidates: [WordEntry]) -> Int {
        Int((Double(candidates.count) / Double(pageSize)).rounded(.up))
    }
}
