import Foundation

/// 「単語を追加」画面で、検索語から自作語を作る導線を出すかと、その文言を決める。
///
/// 単語帳にある語・ない語で入口を分けず、検索 → あれば選ぶ・無ければその場で作る、の 1 本にするため、
/// 検索語があれば結果の有無にかかわらず作成の導線を出す。画面から切り離して単体テストできるようにしている。
enum WordPicker {
    struct CreateAction: Equatable {
        /// 前後の空白を落とした検索語。エディタの下書きに入れる
        let text: String
        let title: String
        /// 補足（同じ綴りの語が結果にあるとき、そちらを選ぶよう促す）
        let note: String?
    }

    /// 検索語が空なら `nil`。`results` は検索結果（同梱語 + 自作語）
    static func createAction(
        query: String,
        results: [WordEntry],
        assistAvailable: Bool
    ) -> CreateAction? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let title = assistAvailable ? "「\(text)」を AI で調べる" : "「\(text)」を自分で作る"
        let spelling = WordStore.normalizedSpelling(text)
        let hasSameSpelling = results.contains { WordStore.normalizedSpelling($0.word) == spelling }
        let note = hasSameSpelling ? "「\(text)」は上の一覧にあります。ふつうはそちらを選んでください。" : nil
        return CreateAction(text: text, title: title, note: note)
    }
}
