# グループ（マイ単語帳）で学習する

作成日: 2026-11-02

## 目的・背景

今は「アプリが毎日おまかせで出す」学習しか無く、
「来週の小テストの範囲」「教科書の Unit 3」のように **自分で決めた範囲をまとめて覚える** ことができない。
また同梱の 2,443 語に無い単語・フレーズは登録できない。

そこで、ユーザーがグループを作って単語・フレーズを登録し、グループ単位で学習できるようにする。

## 決定事項（ユーザー確認済み）

- **登録できる語**: 同梱語（単語帳から選ぶ）＋ 自作語（英語・意味・品詞・例文を自分で入力）
- **学習方法は 2 つ**
  1. **学習する（SRS 共有）**: グループ内の「期限が来た復習」と「未学習語」だけを、いつものセッション
     （提示 → 直後クイズ → 再出題）で出す。進捗（成長ステージ・次回復習日）は単語ごとに共通なので、
     庭・統計・毎日の学習にもそのまま反映される
  2. **ドリル（進捗を動かさない）**: グループ内の全語をランダム順の 4 択で一周する練習。
     SRS の進捗も回答ログも残さない（テスト前の総ざらい用）

## 対応方針

### データ（SwiftData）

- `WordGroup`: `id(UUID)` / `name` / `wordIds: [String]`（追加順）/ `createdAt` / `updatedAt`
- `CustomWord`: `wordId`（`custom-<uuid>`、unique）/ `word` / `meaning` / `pos` / `example` / `exampleJa` / 日時
  - `entry` で `WordEntry` に変換し、以降は同梱語と同じ経路（セッション・クイズ・単語詳細）で扱う
- 進捗 `WordProgress` / ログ `AnswerLog` は wordId キーのままなので変更なし

### 単語の索引（WordStore）

- `WordEntry.level` を `CefrLevel?` にする（自作語はレベル無し。同梱 JSON は従来どおり必ず入る）
- `WordStore.including(customWords:)` で同梱の索引を使い回しつつ自作語を重ねた索引を作る
  - レベル別プール（毎日の新規学習・既知語登録）には自作語を **入れない**（毎日のおまかせには混ぜない）
  - ただし一度学習した自作語の復習は毎日の学習にも出る（SRS 共有のため）
- ルート直下で `CustomWord` を `@Query` し、合成した索引を Environment（`\.wordStore`）で配る。
  セッション・単語帳・単語詳細・締め画面はここから引く
- 誤答肢: 同梱語は従来どおり。自作語は「全語の同品詞 → 全語」から選ぶ

### グループ単位の学習

- `GroupStudy.plan(...)`: 進捗をグループ内に絞って `SessionBuilder` に渡す
  - 新規語はグループの追加順、1 回のセッションの上限は設定の「1 日の新規語数」（足りなければもう一度押せば続きが出る）
  - 今日すでに学習した数では絞らない（範囲を覚え切りたい用途のため）。
    グループで学習した新規語は毎日の学習の「今日の新規語」枠を消費する（1 日の負荷が膨らみすぎない）
- `SessionRunner` に `Mode.drill` を追加: 提示カード無し・全語クイズ・不正解は末尾で再出題（2 回まで）、
  `engine.record` を呼ばない。出題形式は現在のステージから決める（未学習は英→日）
- 締め画面はドリル時「回答数・正答率・間違えた語」を出す

### 画面

- 下部タブに「グループ」を追加（ホーム / 単語帳 / **グループ** / 統計 / 設定）
- グループ一覧: 名前・語数・学習済み数・今日の復習数。＋で新規作成、スワイプで削除
- グループ詳細: 「学習する（N 語）」「ドリル（M 語）」ボタン、語の一覧（スワイプで外す）、
  メニューから「単語帳から追加」「自分で単語を作る」「名前を変更」
- 単語帳から追加: 検索付きの全語リストでチェックを付け外し
- 自作語エディタ: 英語・意味（必須）、品詞、例文・例文の訳（任意）。同じ綴りの同梱語があれば案内する
- 単語帳: 「マイ単語」チップを追加し、自作語も一覧・検索できる
- 単語詳細: 「グループに追加」メニュー。自作語は編集・削除できる
  - 自作語の削除はグループから外し、進捗・ログも消す（解決できない ID を残さない）
- グループを削除しても単語・進捗は残る（自作語は単語帳の「マイ単語」に残る）

### バックアップ

- `BackupArchive` を version 2 にし、`groups` / `customWords` を追加（v1 のファイルも読める）

## 影響範囲

- Models: `WordEntry`（level optional）、新規 `WordGroup` / `CustomWord`
- Core: `WordStore`、`QuizBuilder`、`BackupArchive`、新規 `GroupStudy` / `GroupEditor`
- Features: `RootView`（タブ・Environment）、`SessionRunner` / `SessionView` / `QuizCardView` / `SessionSummaryView`、
  `WordListView` / `WordDetailView` / `WordCardView`（例文が空なら出さない）、新規 `Features/Groups/*`
- App: `VocabBlossomApp`（ModelContainer に新モデル）、`DebugSeed`（groups 画面）

## テスト方針

- Swift Testing（in-memory ModelContainer）
  - `WordStore.including`: 自作語が引ける・レベル別プールに混ざらない
  - `GroupStudy.plan`: グループ外の復習・未学習語が出ない、期限前の語は出ない、新規語の上限
  - `GroupEditor`: 作成 / 追加（重複しない）/ 外す / 自作語の作成・編集・削除（グループ・進捗・ログから消える）
  - `SessionRunner` ドリル: 進捗・ログが増えない、全語出る、不正解の再出題、間違えた語の記録
  - `QuizBuilder`: 自作語でも 4 択が作れる、例文が空なら穴埋めにならない
  - `BackupService`: v2 の往復、v1 ファイルの読み込み
- 既存テストが通ること・SwiftLint 警告 0
- シミュレータで グループ作成 → 追加 → 自作語 → 学習 → ドリル を確認

## Step

1. データ層: モデル追加・`WordEntry.level` optional・`WordStore.including`・Environment・`GroupEditor`
2. 学習: `GroupStudy`・`SessionRunner` ドリル・セッション画面の対応
3. 画面: グループ一覧 / 詳細 / 語の追加 / 自作語エディタ / タブ追加 / 単語帳・単語詳細の対応
4. バックアップ v2・DebugSeed
5. テスト・SwiftLint・シミュレータ確認
