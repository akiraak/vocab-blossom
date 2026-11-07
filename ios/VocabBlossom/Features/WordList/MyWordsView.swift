import SwiftData
import SwiftUI

/// マイ単語（自分で作った単語）の一覧。設定の「データ」から開く。
///
/// 同梱語を探すのはグループの「単語を追加」で足りるので、ここには自作語だけを出す。
/// 編集・削除は行から開く単語詳細の右上で行う
struct MyWordsView: View {
    @Query private var progresses: [WordProgress]

    @State private var query = ""

    @Environment(\.wordStore) private var store

    private var progressByWordId: [String: WordProgress] {
        Dictionary(progresses.map { ($0.wordId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let progressByWordId = progressByWordId
        let words = WordStore.filter(store.customWords, query: query)
        Group {
            if store.customWords.isEmpty {
                ContentUnavailableView {
                    Label("マイ単語はまだありません", systemImage: "character.book.closed")
                } description: {
                    Text("単語帳にない単語・フレーズは、グループの「単語を追加」で作れます。")
                }
            } else if words.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    Section {
                        ForEach(words) { word in
                            NavigationLink {
                                WordDetailView(word: word)
                            } label: {
                                WordRow(word: word, progress: progressByWordId[word.id])
                            }
                        }
                    } header: {
                        Text("\(words.count) 語")
                    }
                }
            }
        }
        .navigationTitle("マイ単語")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "単語・意味・例文を検索")
    }
}
