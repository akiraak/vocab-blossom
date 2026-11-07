# アプリ全体をグループ中心の作りに変え、読み上げをすべて Gemini の声にする

作成日: 2026-11-07

## 目的・背景

- 今のアプリは「CEFR のデッキから毎日おまかせで新しい単語を出す」ことを軸に作ってある（ホームの「今日の学習」・オンボーディングのレベル選択・単語帳タブ・1 日の新しい単語の数）。グループ機能は 2026-11-02 にあとから足した 1 タブにすぎない
- 実際にはグループ機能（学習する・ドリル・穴埋め・読み上げ）をメインに使っていて、おまかせ学習・単語帳タブはほとんど使っていない
- そこで、グループを中心に使う作りに組み替える
- あわせて、学習中の読み上げに残っている OS 内蔵の声（`AVSpeechSynthesizer`）を、グループの読み上げと同じ Gemini の声（Chobi / Naruko）に変える

## 決めたこと（2026-11-07 にユーザーと決定）

| 項目 | 決定 |
|---|---|
| ホーム | グループ中心に作り直す。グループ一覧と、全グループの復習をまとめた「今日の復習」を置く。CEFR デッキからおまかせで新しい単語を出すのはやめる。庭は残し、グループで学んだ語で育てる |
| 単語帳タブ | タブから外す。語を探すのはグループの「単語を追加」で足りる |
| CEFR 学習の機能 | オンボーディングのレベル選択・知っている単語の一括登録・1 日の新しい単語の数の設定を外す（進捗のデータは消さない） |
| 読み上げ | すべて Gemini の TTS にする（今のグループの読み上げ・穴埋めの回答後の読み上げと同じしくみ） |

## 今の作り（調べた結果）

### 画面

- タブ: ホーム / 単語帳 / グループ / 統計 / 設定（`App/RootView.swift`）
- ホーム（`Features/Home/HomeView.swift`）: 庭・ストリークなど 3 つの数字・「今日の学習」（`Dashboard.summary` が `WordStore.newWordPool(level:)` と全体の進捗から復習 + 新しい単語を組む）
- グループ一覧（`Features/Groups/GroupListView.swift`）: グループごとの語数・学習済み・復習の数・回答数・達成度
- グループ詳細（`Features/Groups/GroupDetailView.swift`）: 学習する（`GroupStudy.plan`。新しい単語の上限に `settings.newWordsPerDay`、復習の上限に `settings.reviewLimitPerDay` を使っている）・ドリル・穴埋め・読み上げ
- 単語帳（`Features/WordList/WordListView.swift`）: 同梱語とマイ単語の一覧。マイ単語の一覧が見られるのはここだけ
- オンボーディング（`Features/Onboarding/OnboardingView.swift`）: レベルを選ぶ → 知っている単語の一括登録（`Features/KnownWords/`）
- 設定（`Features/Settings/SettingsView.swift`）: レベル・1 日の新しい単語・知っている単語の一括登録・音声・データ・同期・AI

### 読み上げ

| 場面 | 今の声 | 呼んでいるところ |
|---|---|---|
| グループの読み上げ | Gemini | `GeminiReadAloudSpeaker.shared`（`ReadAloudView`） |
| 穴埋めの回答後 | Gemini | `GeminiReadAloudSpeaker.quiz`（`SessionView.speakFillBlankAnswer`） |
| 提示カード（単語 → 例文） | 内蔵 | `SessionView.speak` → `SpeechService` |
| 英→日の出題時（単語） | 内蔵 | `Quiz.speechOnPrompt` → `SessionView.speak` |
| リスニングの出題時（単語 → 例文） | 内蔵 | 同上 |
| リスニングの「もう一度聞く」 | 内蔵 | `QuizCardView` → `SpeechService` |
| 穴埋め以外の回答後（単語 → 例文） | 内蔵 | `SessionView.feedbackAfterAnswer` → `SpeechService` |
| スピーカーのボタン（単語カード・単語詳細） | 内蔵 | `SpeakButton`（`WordCardView.swift`） |

- Gemini の声は 1 文 2〜3.5 秒かかる。端末に残した音声（`ReadAloudVoiceStore`）があればすぐ鳴る
- 音声が取れない文（オフライン・サーバーの失敗・キー未設定）は内蔵の声で読む（`ReadAloudSpeechEngine`）
- サーバーの回数制限は 10 分 600 回（`SPEECH_RATE_LIMIT`）

## 対応方針

### Phase 1: 学習中の読み上げを Gemini の声にする

- 詳しいプランと結果: [learning-voice-gemini.md](archive/learning-voice-gemini.md)（2026-11-07 実装済み。待つのは 3 秒まで）

- 学習の読み上げを `GeminiReadAloudSpeaker.quiz` に寄せる。`SessionView.speak`・`QuizCardView`・`SpeakButton` の `SpeechService` の呼び出しを置き換える
  - 読む文は `ReadAloudLine`（単語・例文）で組む。`ReadAloudScript` に「単語だけ」「単語 → 例文」を作る関数を足す
- **待ち時間をなくすための先読み**（ここがいちばん大事）
  - 提示カード・英→日・リスニングは画面が出た瞬間に鳴らしたいので、生成を待つと 2〜3 秒黙ってしまう
  - セッションを始めたら、出す予定の語の分を先頭から順に先読みする（今の `prefetch` を使う。同時に取るのは 2 本まで）
  - 学習の場面では、読む人を語ごとに固定する（語の ID から決める）。提示カード・回答後・リスニングで同じ音声を使い回せ、取る数が半分になる。グループの読み上げはこれまでどおり 1 語ごとにランダム
  - 間に合わなかった文は今と同じく内蔵の声で読む（オフラインで黙らないよう、内蔵の声への切り替えは残す）
- 回数制限: 20 語のセッションで「単語 + 例文」×20 = 40 回ほど。600 回で足りる見込み。足りなければサーバーの上限を上げる（サーバーのデプロイが要る）
- 使わなくなった `SpeechService` は消す。`LearningAudioSession` の使い道（学習＝ほかのアプリの音を小さくする）はそのまま
- 設定の「自動で読み上げる」はそのまま効かせる

### Phase 2: ホームをグループ中心にする

- 詳しいプランと結果: [group-home.md](archive/group-home.md)（2026-11-07 実装済み。庭はいちばん下）

- タブを「ホーム / 統計 / 設定」にする（グループタブはホームに入れる。単語帳タブは Phase 3 で外す）
- ホームの並び
  1. **今日の復習**: 期限が来た語をまとめて復習するカード。グループに入っていない語でも、学習を始めた語（CEFR 学習で始めた語を含む）は出す。そうしないと、今までの進捗が復習されないまま残ってしまう。新しい単語は出さない（新しい単語はグループの「学習する」で始める）
  2. **グループ一覧**: 今の `GroupListView` の行（語数・復習の数・回答数・達成度）。作る・削除する・並べる操作もここ
  3. **庭とストリーク**: 小さくまとめて上か下に置く（どちらにするかは画面を見て決める）
- `Dashboard.summary` から新しい単語の計算を外し、復習だけを組む
- グループ詳細はそのまま、ホームから開く

### Phase 3: 単語帳タブを外す

- 詳しいプランと結果: [remove-word-list-tab.md](archive/remove-word-list-tab.md)（2026-11-07 実装済み。入口は設定の「データ」の先頭）

- タブから外す
- マイ単語の一覧と編集は、設定の「データ」に「マイ単語」として入口を置く（今の `WordListView` を、マイ単語だけを出す形で使う）
- 単語詳細（`WordDetailView`）は、グループ詳細の行から開けるのでそのまま

### Phase 4: CEFR 学習の機能を外す

- 詳しいプランと結果: [remove-cefr-learning.md](archive/remove-cefr-learning.md)（2026-11-07 実装済み。上限は `StudyLimits` の固定値）

- オンボーディング: レベル選択と知っている単語の一括登録を外し、短い説明と「最初のグループを作る」にする。もう使っている端末（`hasOnboarded == true`）は出さない
- 設定: レベル・1 日の新しい単語・知っている単語の一括登録を外す
- グループの「学習する」の上限: 新しい単語は 1 回 10 語に固定（今の既定値）、復習は今の算出式で 60 語に固定。設定項目は作らない
- 消すもの: `Features/KnownWords/`・`WordStore.newWordPool`・`AppSettings` の `newWordsPerDay` の選択肢など。DebugSeed の不要な variant も消す
- 残すもの: バックアップの形式（`level`・`newWordsPerDay` も今までどおり書き出す・読み込む）。前の版のバックアップを読めるように、形式の版は変えない
- 同梱語の JSON（`data/decks/`）は「単語を追加」の検索・誤答肢・CEFR で始めた語の進捗に使うので残す

### Phase 5: 仕様書を直す

- 詳しいプランと結果: [group-centric-specs.md](archive/group-centric-specs.md)（2026-11-07 実施）

- `docs/specs/app-concept.md` の §3（学習ループ）・§4（音声）・§5・§6（画面構成）・§7（音声）・§9 を新しい作りに合わせる
- `README.md` に画面の説明があれば直す

### Phase 6: 実機確認

- 読み上げ: 提示カード・英→日・リスニング・回答後で黙る時間が無いか、内蔵の声に落ちる回数、オフラインで内蔵の声で読むこと
- ホーム: 今日の復習・グループ一覧・庭が見やすいか、グループ詳細への行き来
- 前の版から更新したときに進捗・グループ・マイ単語が残っていること
- Phase 2〜4 でシミュレータでは見ていないところ: 復習がある日の「今日の復習」カード、オンボーディングの「最初のグループを作る」でホームに進むこと、マイ単語が無いときの案内とマイ単語から単語詳細へ進むこと
- 前に「1 日の新しい単語」を 10 語より多くしていた端末で、復習の上限が 60 語になり、超えた分が次の日に回ること

## 影響範囲

- iOS
  - 読み上げ: `Core/SpeechService.swift`（削除）・`Core/GeminiReadAloudSpeaker.swift`・`Core/ReadAloud.swift`・`Features/Session/SessionView.swift`・`Features/Session/QuizCardView.swift`・`Features/Components/WordCardView.swift`・`Core/SoundEffect.swift`（音声セッションの扱いだけ確認）
  - 画面: `App/RootView.swift`・`Features/Home/`・`Features/Groups/GroupListView.swift`・`Features/WordList/`・`Features/Onboarding/`・`Features/KnownWords/`（削除）・`Features/Settings/SettingsView.swift`・`App/DebugSeed.swift`
  - ロジック: `Core/Dashboard.swift`・`Core/SessionBuilder.swift`・`Core/GroupStudy.swift`・`Core/AppSettings.swift`・`Core/WordStore.swift`・`Core/BackupArchive.swift`
- サーバー: 基本は変えない。回数制限が足りないときだけ `server/src/ai/speech.ts` の `SPEECH_RATE_LIMIT` を上げてデプロイする
- 進捗・グループ・マイ単語・回答の記録・バックアップの形式は変えない（データの移行は無い）

## テスト方針

- Swift Testing
  - 読み上げ: 学習の場面で読む人が語ごとに固定されること・先読みの順番・取れない文が内蔵の声になること（`GeminiReadAloudTests` に足す。`SpeechServiceTests` は消す）
  - ホーム: 今日の復習に新しい単語が入らないこと・グループに入っていない語の復習も出ること（`DashboardTests`）
  - グループの学習の上限が固定値になること（`SessionBuilderTests` / グループ学習のテスト）
  - バックアップ: 前の版の形式を読めること（`BackupTests`）
  - 外した機能のテスト（`KnownWordsPickerTests` など）は消す
- SwiftLint 警告 0
- シミュレータで DebugSeed を使ってホーム・設定・オンボーディング・学習の画面を確認する
- 実機確認は Phase 6
