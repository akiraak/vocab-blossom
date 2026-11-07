# CEFR 学習の機能を外す

作成日: 2026-11-07
親プラン: [group-centric-redesign.md](group-centric-redesign.md) の Phase 4

## 目的・背景

- Phase 2 でホームから「CEFR デッキからおまかせで新しい単語を出す」のをやめたので、そのための設定・画面が残っているだけになった
  - オンボーディングのレベル選択・知っている単語の一括登録（`Features/KnownWords/`）
  - 設定の「レベル」「1 日の新しい単語」「知っている単語をまとめて登録」
- グループを中心に使う作りに合わせて外す。進捗・グループ・マイ単語・回答の記録・バックアップの形式は変えない

## 対応方針

### オンボーディング

- レベル選択と知っている単語の一括登録を外す
- 短い説明（グループを作って覚えたい語を入れる → 学習する・ドリル・穴埋め・読み上げ → 覚えた語が庭の花になる）と、グループの名前の入力欄・「最初のグループを作る」を置く
  - 押すとグループを作ってホームへ進む（名前が空なら今までどおり「新しいグループ」）
  - 「あとで作る」でグループを作らずにホームへ進める
- もう使っている端末（`hasOnboarded == true`）には出さない（今までどおり）

### 設定

- 「学習」の節（レベル・1 日の新しい単語・知っている単語の一括登録）をまるごと外す

### 学習の上限

- `StudyLimits`（`Core/SessionBuilder.swift`）に固定値を置く。設定項目は作らない
  - グループの「学習する」の新しい単語: 1 回 10 語（今の既定値）
  - 復習の 1 日上限: 60 語（今の算出式 `max(60, 新しい単語 × 6)` の既定値での値）
- `GroupStudy.Input` の `newWordsLimit`・`reviewLimit` の既定値を `StudyLimits` にし、グループ詳細は既定値のまま使う
- ホームの今日の復習（`Dashboard`）も `StudyLimits.reviewsPerDay` を使う
- 前に「1 日の新しい単語」を 10 語より多くしていた人は、復習の上限が 60 語に下がる。超えた分は今と同じく次の日に回る（「ほかに N 語たまっています」）

### 消すもの

- `Features/KnownWords/`（画面と候補の組み立て）と `KnownWordsPickerTests`
- `WordStore.newWordPool(level:)` とそのテスト。`words(level:)` は誤答肢の選び方で使うので残す
- `AppSettings` の `newWordsPerDayChoices`・`reviewLimit(forNewWordsPerDay:)`・`reviewLimitPerDay` など、上限を設定から決めるしくみ
- `CefrLevel.summary`（レベル選択の説明。ほかで使っていない）
- DebugSeed の `known-words`・`session-new`（ホームの復習には新しい単語が出なくなったので、提示カードから始まる状態は `group-learn` で見る）と、`session-summary` 用の「今日の新しい単語を使い切った状態」を作る処理

### 残すもの

- バックアップの形式（`settings` の `level`・`newWordsPerDay`・`reviewLimitPerDay`）。形式の版（4）は変えない
  - 前の版のファイルを読めるよう、`AppSettings` の `level`・`newWordsPerDay` は値の保存だけ残し（画面には出さない）、今までどおり書き出す・読み込む
  - `reviewLimitPerDay` は書き出すだけ（固定の 60 を書く）。読み込みでは使わない（今までどおり）
- 同梱語の JSON（`data/decks/`）とレベルの情報（単語を追加の検索・誤答肢・単語詳細の「レベル」に使う）
- 単語詳細の「もう知ってる」（1 語ずつ知っている語にする）

## 影響範囲

- `App/RootView.swift`・`App/DebugSeed.swift`・`App/VocabBlossomApp.swift`
- `Features/Onboarding/OnboardingView.swift`（作り直し）・`Features/KnownWords/`（削除）・`Features/Settings/SettingsView.swift`
- `Features/Home/HomeView.swift`・`Features/Groups/GroupDetailView.swift`
- `Core/AppSettings.swift`・`Core/SessionBuilder.swift`・`Core/GroupStudy.swift`・`Core/WordStore.swift`・`Core/BackupArchive.swift`・`Models/WordEntry.swift`
- テスト: `AppSettingsTests`・`SessionBuilderTests`・`WordGroupTests`・`WordStoreTests`・`KnownWordsPickerTests`（削除）・`BackupTests`

## テスト方針

- Swift Testing
  - グループの「学習する」が、上限を渡さなければ新しい単語 10 語・復習 60 語で組まれること（`WordGroupTests`）
  - 固定の上限（新しい単語 10 語・復習 60 語）でも、定常状態（復習 = 新しい単語 × 5）で新しい単語が止まらないこと（`SessionBuilderTests`）
  - バックアップ: 書き出すと `level`・`newWordsPerDay` と `reviewLimitPerDay`（60）が入り、前の版のファイルを読めること（`BackupTests`）
  - 外した機能のテスト（`KnownWordsPickerTests`・新規学習プールのテスト）は消す
- SwiftLint 警告 0
- シミュレータで、オンボーディング（`hasOnboarded` が false の状態）・設定・グループの学習を見る

## 結果（2026-11-07）

- オンボーディングを「使い方の 3 行（グループを作る → グループで学習する → 庭が育つ）＋ 最初のグループの名前 ＋『最初のグループを作る』『あとで作る』」に作り直した
- 設定の「学習」の節（レベル・1 日の新しい単語・知っている単語の一括登録）を外した
- `StudyLimits`（新しい単語 1 回 10 語・復習 1 日 60 語）を置き、グループの「学習する」・ホームの今日の復習・バックアップの `reviewLimitPerDay` で使うようにした
- `Features/KnownWords/`・`KnownWordsPickerTests`・`WordStore.newWordPool`・`AppSettings` の上限の算出・`CefrLevel.summary` を消した。`AppSettings` の `level`・`newWordsPerDay` はバックアップのためだけに残した（形式の版は 4 のまま）
- DebugSeed: `known-words`・`session-new` と「今日の新しい単語を使い切った状態」を消し、オンボーディングを見る `onboarding` を足した
- Swift Testing 300 件すべて通過（消した機能のテストを除き、固定の上限・バックアップの書き出しのテストを足した）・SwiftLint 警告 0
- シミュレータで `onboarding`（新しいオンボーディング）・`settings`（「学習」の節が無い・マイ単語の入口）・`group-learn`（新しい単語の提示カード、残り 9 問 = 10 語）を確かめた
  - 「最初のグループを作る」を押してホームに進むところは、シミュレータでタップしていないため画面では見ていない。親プランの Phase 6（実機確認）で見る
