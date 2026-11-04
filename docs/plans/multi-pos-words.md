# マイ単語に複数の品詞（意味）を持たせる

作成日: 2026-11-03

## 目的・背景

- commute は「動詞: 通勤する」「名詞: 通勤」のように、1 つの綴りに品詞の違う意味がある。今のマイ単語（自作語）は
  品詞・意味・例文を **1 組だけ** しか持てない
- AI で調べると品詞ごとに候補が返る（commute なら動詞と名詞の 2 つ）。今は別々のマイ単語として作るしかなく、
  同じ綴りの語が 2 つグループに並び、学習の進み具合も別々になる
- 出題の誤答肢は「同じ品詞の語」から選んでいる（`QuizBuilder`）。品詞が 1 つだけだと、
  名詞の意味で出題しているのに動詞の誤答肢が並ぶ、といったずれが起きうる
- 発端は [word-assist-double-select](archive/word-assist-double-select.md) の Step 2

## 今どうなっているか（調査結果）

- 単語帳の語（同梱語 2,443 語）は 1 語 1 品詞。同じ綴りの語は 1 つも無い
- 品詞を 1 つ前提にしている場所
  - iOS: `WordEntry.pos`・`CustomWord.pos`・`WordDraft.pos`、`QuizBuilder`（誤答肢を同じ品詞から選ぶ）、
    `WordCardView`（品詞の表示）、エディタの品詞ピッカー、同期（`SyncModels`・`SyncEngine`）、バックアップ（`BackupArchive` v2）
  - サーバー: `custom_words.pos` 列、同期の型（`sync/types.ts`）、管理画面のフォーム（`admin/pages.ts`）
  - AI（`ai/word-assist.ts`）は今も品詞ごとに候補を返すので、そのまま使える

## 対応方針

### 決めること 1: どう持たせるか → 「意味ごとに品詞を持つ」を推奨

| 案 | 中身 | 良いところ | 困るところ |
|---|---|---|---|
| **A. 意味ごとに品詞を持つ（推奨）** | 1 語に「品詞・意味・例文・訳」の組を複数持つ | 辞書と同じ形。AI の候補（品詞ごとに意味・例文がある）をそのまま入れられる。出題で品詞と意味がずれない | 直す場所が多い（エディタ・出題・同期） |
| B. 品詞だけ複数 | 品詞を複数選べるだけ。意味・例文は 1 つ | 変更が小さい | 「通勤する／通勤」のどれが動詞か分からない。誤答肢の品詞をどれに合わせるか決まらない |
| C. 品詞ごとに別の語（今のまま） | 動詞の commute と名詞の commute を別に作る | 何も直さなくてよい | 同じ綴りが 2 つ並ぶ。進み具合が別々 |

### 決めること 2: 対象 → 「マイ単語だけ」を推奨

- 単語帳の語は 1 語 1 品詞のデータで、増やすには 2,443 語のデータ整備が要る。今回はマイ単語だけにする
- ただし作りは共通にしておき、単語帳の語は「意味が 1 つの語」として同じように扱う（あとで単語帳に広げられる）

### 形（案 A）

- 意味 1 つ分を `WordSense`（品詞・意味・例文・例文の訳）とする
- 1 つ目の意味は今の `pos`・`meaning`・`example`・`exampleJa` のまま残し、**2 つ目以降を `extraSenses` に足す**
  - 今あるマイ単語・同期データ・バックアップはそのまま読める（2 つ目以降が空なだけ）
  - 一覧の「意味」の列などは 1 つ目の意味を出せば今までどおり動く
- 学習の進み具合（SRS）は 1 語で 1 つ（意味ごとには分けない）

### 画面・出題の変わり方

- **「単語を追加」**: AI が同じ綴りで品詞違いの候補を返したら、**1 枚のカードにまとめる**（「commute　動詞: 通勤する／名詞: 通勤」）。
  意味ごとに入れる・入れないを選べ、「追加」で 1 つのマイ単語になる
- **エディタ（直す・自分で作る）**: 「意味」の欄を品詞・意味・例文・訳のまとまりで並べ、「意味を追加」「この意味を消す」を付ける（最低 1 つ）
- **単語の表示**（単語カード・単語詳細）: 品詞ごとに意味と例文を並べる
- **出題**: 1 問ごとに意味を 1 つ選んで出す
  - 英→日: 選んだ意味が正解。誤答肢はその意味の品詞から選び、その語のほかの意味は誤答肢に入れない
  - 日→英: 選んだ意味を出して、英語を答える
  - 穴埋め: 選んだ意味の例文を使う（例文に単語が見つからなければ、使える例文のある意味を選ぶ）
- **管理画面**: マイ単語の作成・編集フォームで意味を複数入れられるようにし、一覧・グループ詳細で表示する

## Phase

- Phase 1: データ（iOS・サーバー・同期・バックアップ）
  - iOS: `WordSense`、`CustomWord.extraSenses`（既定は空）、`WordEntry.extraSenses` と `senses`（1 つ目 + 追加分）
  - サーバー: マイグレーションで `custom_words.extra_senses`（JSON、既定 `[]`）を追加し、同期の型で受け渡す
  - 同期で `extraSenses` が無いデータは空として読む。バックアップは形式 v3（v2 も読める）
  - サーバーを先に g3plus へ反映する（新しいアプリから送る `extraSenses` を受け取れるように）
- Phase 2: 作る・直す・表示（iOS）
  - 「単語を追加」で同じ綴りの候補を 1 枚にまとめる、エディタで意味を増やす・消す、単語カード・単語詳細の表示
- Phase 3: 出題（iOS）
  - 1 問ごとに意味を選ぶ、誤答肢の品詞をその意味に合わせる、穴埋めの例文の選び方
- Phase 4: 管理画面
  - マイ単語の作成・編集フォームで意味を複数に、一覧・グループ詳細の表示

### Phase 1 の結果（2026-11-03）

- サーバー: `WordSense` 型と `parseSense`、`CustomWord.extraSenses`（無ければ空、10 個まで、意味ごとに品詞・意味を検証）、
  マイグレーション `custom-words-extra-senses`（`custom_words.extra_senses TEXT NOT NULL DEFAULT '[]'`）。
  管理画面での編集は `extraSenses` をそのまま残す。Vitest 163 件成功・型チェック OK（Node 24 で実行。シェルの既定の Node 20 では better-sqlite3 が読めない）
- iOS: `WordSense`、`WordEntry.extraSenses`・`primarySense`・`senses`（同梱語の JSON は `extraSenses` 無しで読む）、
  `CustomWord.extraSensesData`（JSON。nil は無し）と `extraSenses`、同期の `extraSenses`（無ければ空）、バックアップ v3（v2 も読める）。
  Swift Testing 188 件成功・SwiftLint 警告 0
- 残り: サーバーを g3plus へ反映（push → g3plus で `git pull` → 再ビルド。起動時にマイグレーションが当たる）

## 影響範囲

- iOS: `Models/WordEntry.swift`・`CustomWord.swift`、`Core/GroupEditor.swift`・`QuizBuilder.swift`・`BackupArchive.swift`、
  `Core/Sync/`（`SyncModels`・`SyncEngine`・`WordAssistClient`）、`Features/Groups/`（`WordAddSession`・`WordPickerView`・`CustomWordEditorView`）、
  `Features/Components/WordCardView.swift`、`Features/WordList/WordDetailView.swift`
- server: `sync/store.ts`（マイグレーション）・`sync/types.ts`、`admin/`（フォーム・表示）、関連テスト
- 単語帳の語（`data/decks`）は変えない

## テスト方針

- iOS（Swift Testing）
  - 意味が 1 つの語・複数の語のどちらも、作る・直す・同期・バックアップで中身が崩れない（v2 のバックアップ・`extraSenses` の無い同期データも読める）
  - 「単語を追加」: 同じ綴りの候補が 1 枚になり、選んだ意味だけでマイ単語が 1 つ作られる
  - 出題: 選んだ意味の品詞から誤答肢を選ぶ / ほかの意味が誤答肢に混ざらない / 穴埋めは例文のある意味を使う
- server（Vitest）: マイグレーション、`extraSenses` の受け渡し（無い・空・複数）、不正な品詞を弾く、管理画面のフォーム
- 既存テストがすべて通る・SwiftLint 警告 0
- 画面確認: シミュレータで commute（動詞・名詞）を 1 語として追加し、単語詳細・出題を確認。実機で同期まで確認
