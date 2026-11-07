# ホームをグループ中心にする

作成日: 2026-11-07
親プラン: [group-centric-redesign.md](../group-centric-redesign.md) の Phase 2

## 目的・背景

- グループ機能をメインに使っているのに、ホームは「CEFR デッキからおまかせで出す今日の学習」と庭で、グループは別のタブにある
- 起動したらすぐグループを選べて、全グループの復習もまとめてできるホームにする

## 対応方針

### タブ

- 「グループ」タブをやめてホームに入れる。タブは「ホーム / 単語帳 / 統計 / 設定」（単語帳は Phase 3 で外す）

### ホームの並び（上から）

1. **今日の復習**: 期限が来た語をまとめて復習するカード
   - 学習を始めた語（進捗のある語）すべてが対象。グループに入っていない語（CEFR 学習で始めた語）も出す
   - 新しい単語は出さない（グループの「学習する」で始める）。1 日の上限（今の `reviewLimitPerDay`）と、今日こなした復習の数を引くのは今のまま
   - 復習が無い日は「今日の復習は終わりました」とし、グループの「学習する」で新しい単語を始めるよう案内する
   - ストリークと今日の回答数をこのカードに小さく出す
2. **グループ**: 今の `GroupListView` の行（語数・学習済み・復習の数・回答数・達成度）。作る（右上の ＋）・スワイプで削除・引っ張って同期もここ。グループが無ければ「グループを作る」を出す
3. **庭**: 今の庭と成長の内訳。いちばん下に置く（毎日見るのは復習とグループなので）

- 全体を `List` にする（グループの行のスワイプ削除を残すため）。今日の復習と庭はカードの見た目のまま行に置く
- 今日の復習のセッションはグループの記録（`GroupAnswerLog`）には残さない（どのグループの語か決まらないため）。閉じるボタンは「ホームにもどる」

### ロジック

- `Dashboard.summary` から新しい単語の計算を外す（`Input` の `newWordPool`・`newWordsPerDay` を消し、`SessionBuilder` には空のプールを渡す）
- `GroupListView` は消し、`GroupRow`・`GroupActivityText` は `Features/Groups/GroupRow.swift` に移す
- DebugSeed: グループの画面を開く variant はホームで開く。`groups` はホームを開く

## 影響範囲

- `App/RootView.swift`・`App/DebugSeed.swift`
- `Features/Home/HomeView.swift`（作り直し）・`Features/Groups/GroupListView.swift`（削除）・`Features/Groups/GroupRow.swift`（新規）
- `Core/Dashboard.swift`・`VocabBlossomTests/DashboardTests.swift`
- `Features/WordList/WordDetailView.swift`（「グループタブで」の案内文）
- データの形は変えない

## テスト方針

- Swift Testing（`DashboardTests`）: 今日の復習に新しい単語が入らない・グループに入っていない語の復習も出る・今日こなした復習の数を引く
- SwiftLint 警告 0
- シミュレータで DebugSeed（`VOCAB_SEED_DEMO=1`、`group-detail` / `fresh` など）を使い、ホームの見た目・グループ詳細への行き来・グループが無いときの表示を確かめる

## 結果（2026-11-07）

- タブを「ホーム / 単語帳 / 統計 / 設定」にし、ホームを「今日の復習 → グループ → 庭」の `List` に作り直した。庭はいちばん下に置いた
- `Dashboard.summary` は復習だけを組む（`Input` の `newWordPool`・`newWordsPerDay` を消した）。`GroupListView` を消し、`GroupRow`・`GroupActivityText` を `Features/Groups/GroupRow.swift` に移した
- セッションの閉じるボタンの既定を「庭にもどる」から「ホームにもどる」に、庭が空のときの案内を「グループで学習すると花が育ちます」に、単語詳細の「グループタブで」を「ホームで」に直した
- Swift Testing 308 件すべて通過・SwiftLint 警告 0
- シミュレータで `groups`（グループ 2 つ・復習なし）・`fresh`（グループなし・庭が空）・`group-detail`（ホームからグループ詳細が開く）を確かめた
  - 復習がある日のカード（「復習する（N 語）」）は、DebugSeed に復習が残ったままホームを開く状態が無いため画面では見ていない（`DashboardTests` で確かめた範囲のみ）。親プランの Phase 6（実機確認）で見る
