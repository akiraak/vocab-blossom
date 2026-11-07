# 単語帳タブを外す

作成日: 2026-11-07
親プラン: [group-centric-redesign.md](group-centric-redesign.md) の Phase 3

## 目的・背景

- 語を探すのはグループの「単語を追加」で足りていて、単語帳タブ（同梱語 2,443 語の一覧）はほとんど使っていない
- ただし自分で作った単語（マイ単語）の一覧が見られるのは単語帳だけなので、入口は残す

## 対応方針

- タブを「ホーム / 統計 / 設定」にする（`MainTabView.TabId.words` を消す）
- 単語帳（`WordListView`）を「マイ単語」の画面（`MyWordsView`）に作り直す
  - 自作語だけを作った順に出す。検索（単語・意味・例文）はそのまま
  - 行から単語詳細（`WordDetailView`）を開く。編集・削除は今までどおり単語詳細の右上から
  - 1 つも無いときは「グループの『単語を追加』で作れます」と案内する
- 入口は設定の「データ」の先頭に「マイ単語（N 語）」として置く
- 一覧の行（`WordRow`）はグループ詳細でも使うので `Features/WordList/WordRow.swift` に分ける
- 「単語帳の『マイ単語』に残ります」（グループを消すときの確認）を「設定の『マイ単語』に残ります」に直す
- 「単語を追加」まわりの「単語帳にない語」という言い方は、収録語（同梱語 + 自作語）を指す言葉として残す
- DebugSeed: `words` を `my-words`（設定 → マイ単語を開く。自作語の入ったグループを作る）に変える

## 影響範囲

- `App/RootView.swift`・`App/DebugSeed.swift`
- `Features/WordList/WordListView.swift`（`MyWordsView.swift` に置き換え）・`Features/WordList/WordRow.swift`（新規）
- `Features/Settings/SettingsView.swift`・`Features/Home/HomeView.swift`（文言）
- `README.md` の DebugSeed の説明
- データの形は変えない

## テスト方針

- 画面だけの変更なので、Swift Testing は今のものがすべて通ることを確かめる
- SwiftLint 警告 0
- シミュレータで `my-words`（自作語の一覧 → 単語詳細）と `fresh`（マイ単語が無いときの案内）、タブが 3 つになったことを見る

## 結果（2026-11-07）

- タブを「ホーム / 統計 / 設定」にした。単語帳（`WordListView`）を、自作語だけを出す「マイ単語」（`MyWordsView`）に作り直し、設定の「データ」の先頭（「マイ単語 N 語」）から開くようにした
- `WordRow` を `Features/WordList/WordRow.swift` に分けた。グループを消すときの案内を「設定の『マイ単語』に残ります」に直した
- DebugSeed の `words` を `my-words` に変えた
- Swift Testing 308 件すべて通過・SwiftLint 警告 0
- シミュレータで `my-words` を開き、タブが 3 つになったこと・自作語 3 語（take care of・homeroom・cram）が並ぶことを確かめた
  - マイ単語が無いときの案内と、行から単語詳細へ進むところは画面では見ていない（DebugSeed に自作語なしでマイ単語を開く状態が無く、シミュレータでタップしていないため）。親プランの Phase 6（実機確認）で見る
