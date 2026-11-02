import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// 同梱語 + 自作語の索引。セッション・単語帳など単語を引く画面はここから取る
    @Entry var wordStore: WordStore = .shared
}

/// 自作語を `@Query` で見張り、同梱語と合わせた索引を配下の画面へ配る。
///
/// 自作語の追加・編集・削除はすぐに全画面（毎日のセッションの復習も含む）へ反映される。
struct WordStoreProvider<Content: View>: View {
    @Query(sort: \CustomWord.createdAt) private var customWords: [CustomWord]

    @ViewBuilder let content: Content

    var body: some View {
        content
            .environment(\.wordStore, WordStore.shared.including(customWords: customWords.map(\.entry)))
    }
}
