# 学習中の読み上げを Gemini の声にする

作成日: 2026-11-07
親プラン: [group-centric-redesign.md](../group-centric-redesign.md) の Phase 1

## 目的・背景

- 「全ての音声読み上げを Gemini の TTS に変更する」の一部。グループの読み上げと穴埋めの回答後はもう Gemini の声（Chobi / Naruko）になっているが、ほかの学習中の読み上げは OS 内蔵の声（`SpeechService` = `AVSpeechSynthesizer`）のまま
- 声がバラバラだと聞きづらく、内蔵の声は不自然なので、すべて Gemini の声にそろえる
- いちばん気をつけるのは待ち時間。Gemini の声は 1 文 2〜3.5 秒かかる。提示カード・英→日・リスニングはカードが出た瞬間に読みたいので、そのまま頼むと毎回黙ってしまう

## 今の作り

| 場面 | 読む文 | 今の声 | 呼んでいるところ |
|---|---|---|---|
| 提示カード | 単語 → 例文 | 内蔵 | `SessionView.speakIfNeeded` → `speak(word:example:)` → `SpeechService` |
| 英→日の出題時 | 単語 | 内蔵 | `Quiz.speechOnPrompt` → 同上 |
| リスニングの出題時 | 単語 → 出題の意味の例文 | 内蔵 | 同上 |
| リスニングの「もう一度聞く」 | 単語 → 例文 | 内蔵 | `QuizCardView`（`.listening`）→ `SpeechService` |
| 穴埋め以外の回答後 | 単語 → 出題の意味の例文 | 内蔵 | `SessionView.feedbackAfterAnswer` → `speak(word:example:)` |
| スピーカーのボタン（単語カード・回答後のカード・単語詳細） | 単語 → 1 つ目の意味の例文 | 内蔵 | `SpeakButton`（`Features/Components/WordCardView.swift`） |
| 穴埋めの回答後 | 単語 → 出題の文章 | Gemini | `GeminiReadAloudSpeaker.quiz` |
| グループの読み上げ | 単語 → 意味 → 例文 → 和訳 | Gemini | `GeminiReadAloudSpeaker.shared` |

- `GeminiReadAloudSpeaker` の今の動き
  - 端末に残した音声（`ReadAloudVoiceStore`）があればそれを鳴らす。無ければサーバー（`POST /api/speech`）へ頼み、届くまで待つ（待つ時間の上限は無い。通信が 20 秒で切れるまで待つ）
  - 取れない文（オフライン・サーバーの失敗・300 字超え）はその文だけ内蔵の声（`ReadAloudSpeechEngine`）で読む。内蔵の声の速さは `SpeechService` と同じ（単語 0.42・例文 0.45）
  - 読む人は 1 語ごとにランダム（3 語続けて同じ人にしない）。決めた人の分がまだ無く、もう 1 人の分が残っていればそちらで読む
  - 端末に残す音声の鍵は「モデル・人・種類・文」。同じ単語・同じ例文なら、グループの読み上げで残した音声を学習でも使える
- `SessionRunner` はこれから出す項目を `queue`（`.present` / `.quiz` と語の ID）に持つ。問題の形式は出す直前に決まる（ステージで決まる）ので、先に分かるのは「どの語を出すか」まで
- サーバーの回数制限は読み上げだけで 10 分 600 回（`SPEECH_RATE_LIMIT`。ほかの AI の API とは別）

## 対応方針

### 読む人は語ごとに固定する（学習の場面だけ）

- 学習（`GeminiReadAloudSpeaker.quiz`）では、読む人を単語の綴りから決める（綴りの FNV-1a ハッシュの偶奇で Chobi / Naruko。`hashValue` は起動ごとに変わるので使わない）
- 提示カード → 出題 → 回答後 → スピーカーのボタンで同じ人の同じ音声を使い回せる。取る数は 1 語あたり「単語 + 例文」の 2 本（意味が複数あれば例文の数だけ増える）で済む
- 決めた人の分がまだ無く、もう 1 人の分が端末にそろっていれば、今と同じくそちらで読む（グループの読み上げで残した音声を使える）
- グループの読み上げ（`shared`）はこれまでどおり 1 語ごとにランダム
- 穴埋めの回答後も `quiz` で読んでいるので、同じく語ごとに固定になる（単語の音声を出題時・回答後で使い回せる）

### 待つのは 3 秒まで（学習の場面だけ）

- 学習では、文の音声が 3 秒たってもそろわなければ、その文は内蔵の声で読む。取りに行った分はそのまま端末に残し、次からは Gemini の声で鳴る
- 待つ上限は初期化のときに渡す（`maxWait`）。グループの読み上げは今までどおり上限なしで待つ（読み上げ画面は少し待っても困らないため）
- 3 秒にする（2026-11-07 にユーザーが決定）。1 文の生成は 2〜3.5 秒なので、先読みが間に合わなかった文もほとんどは Gemini の声で鳴る。そのかわり、カードが出てから最大 3 秒黙ることがある。実機（親プランの Phase 6）で聞いて、長すぎれば見直す

### 先に取っておく（先読み）

- セッション中は、カードを出すたびに次の順で先読みし直す（同時に取るのは今と同じ 2 本まで）
  1. 今のカードで読む文
  2. 穴埋めなら回答後に読む文（今の処理と同じ）
  3. このあと出す 5 語の「単語」と「すべての意味の例文」
- `SessionRunner` に「このあと出す語」（`queue` の先頭から重なりを除いた語の ID）を返すプロパティを足す
- 5 語先まででとどめる。始めたセッションを途中でやめたとき、まとめて頼んだ分が無駄にならないようにするため。1 語を 5〜10 秒で進むのに対し、2 本同時なら 1 語分（2 本）は 3 秒ほどで取れるので追いつく
- グループ詳細を開いたとき、「学習する」で最初に出す 2 語の分も先に取っておく（今の `warmUp` と同じ考え方）。最初のカードで内蔵の声にならないようにするため
- 回数: 学習する（新しい単語 10 語 + 復習）でも 1 語 2〜3 本なので、10 分 600 回に届かない見込み。届くようなら別タスクでサーバーの上限を上げる

### 置き換え

- `ReadAloudScript` に、学習で読む文を作る関数を足す
  - `learningLines(word:example:)`: 単語 → 例文（例文が空なら単語だけ）
  - 先読み用に「単語 + すべての意味の例文」を作る関数
- `SessionView`
  - `speak(word:example:)` を `GeminiReadAloudSpeaker.quiz.speak(...)` に置き換える（提示カード・英→日・リスニングの出題時・穴埋め以外の回答後）
  - `stopSpeaking()` と締め（`.summary`）は `quiz.stop()` / `quiz.finish()` にする
- `QuizCardView` のリスニングの「もう一度聞く」と `SpeakButton` も `quiz` で読む
  - 単語詳細（`WordDetailView`）の `SpeakButton` もセッションの外で `quiz` を使う。画面を閉じたら止める
- 設定の「自動で読み上げる」（`soundEnabled`）はこれまでどおり自動の読み上げだけに効かせる。ボタンで読むのはいつでも鳴らす
- 音声セッションは今の `quiz` と同じ「学習」（ほかのアプリの音は小さくするだけ）。効果音（`SoundEffect`）との兼ね合いは変えない

### `SpeechService` を消す

- 呼び出しが無くなったら `Core/SpeechService.swift` と `SpeechServiceTests` を消す
- `GeminiReadAloudSpeaker` と `ReadAloudSpeechEngine` にある `SpeechService.shared.interrupt()` の呼び出しを外す
- 内蔵の声はオフライン・取れないときの代わりとして `ReadAloudSpeechEngine` に残る

## Step

1. **Step 1: `GeminiReadAloudSpeaker` に学習用の動きを足す**
   - 読む人を語ごとに固定するモード、待つ上限（`maxWait`）、2 人分を取らずに複数の語を先読みする `prefetch`
   - `quiz` をこの設定で作る。`shared` の動きは変えない
   - テストを足す（下のテスト方針）
2. **Step 2: 学習画面の読み上げを置き換え、セッションで先読みする**
   - `ReadAloudScript` に文を作る関数を足す。`SessionRunner` に「このあと出す語」を足す
   - `SessionView`・`QuizCardView`・`SpeakButton`・`WordDetailView` を置き換える。グループ詳細で最初の 2 語を先読みする
3. **Step 3: `SpeechService` を消す**
   - 本体・テスト・`interrupt()` の呼び出し。コメントに残っている `SpeechService` の説明も直す
4. **Step 4: 確かめる**
   - Swift Testing・SwiftLint
   - シミュレータで、DebugSeed の偽の音声（`DebugSpeechFetcher`）を使って提示カード・英→日・リスニング・回答後・スピーカーのボタンで鳴ることを確かめる
   - 本物のサーバーでの待ち時間・聞こえ方は、親プランの Phase 6（実機確認）でまとめて確かめる

## 影響範囲

- iOS
  - `Core/GeminiReadAloudSpeaker.swift`（読む人の固定・待つ上限・先読み）
  - `Core/ReadAloud.swift`（`ReadAloudScript` に関数を足す）
  - `Core/ReadAloudSpeechEngine.swift`（`SpeechService.interrupt()` を外す）
  - `Core/SpeechService.swift`（削除）
  - `Features/Session/SessionView.swift`・`Features/Session/SessionRunner.swift`・`Features/Session/QuizCardView.swift`
  - `Features/Components/WordCardView.swift`（`SpeakButton`）・`Features/WordList/WordDetailView.swift`
  - `Features/Groups/GroupDetailView.swift`（最初の 2 語の先読み）
  - `App/VocabBlossomApp.swift`（`quiz` の作り方が変わるなら）
- サーバー: 変えない（`POST /api/speech` の形・回数制限はそのまま）。デプロイは要らない
- 端末に残す音声の鍵・置き場は変えない。グループの読み上げで残した音声もそのまま使える

## テスト方針

- Swift Testing（`GeminiReadAloudTests` に足す）
  - 学習のモードでは、同じ単語なら何度読んでも同じ人で頼む。綴りが違えば 2 人に分かれる
  - 決めた人の分が無く、もう 1 人の分がそろっていれば、そちらで読む
  - 待つ上限を過ぎた文は内蔵の声で読み、届いた音声は端末に残る（次は Gemini の声で鳴る）
  - 上限なし（グループの読み上げ）は、今までどおり届くまで待つ
  - 複数の語の先読みで、読む予定の人の分だけを、渡した順に頼む
- Swift Testing（そのほか）
  - `ReadAloudScript` の学習用の文（例文が空なら単語だけ、意味が複数あれば例文をすべて）
  - `SessionRunner` の「このあと出す語」（重なりを除く・再出題も入る・締めでは空）
  - `SpeechServiceTests` は消す
- SwiftLint 警告 0
- シミュレータで画面を通して鳴ることを確かめる（Step 4）。実機確認は親プランの Phase 6

## 結果（2026-11-07）

- Step 1〜4 を実装した
  - `GeminiReadAloudSpeaker` に `SpeakerChoice`（`.random` / `.perWord`）と `maxWait` を足し、`quiz` を `.perWord`・3 秒で作る。`prefetch` は複数の語を渡す形にした（`prefetch([[ReadAloudLine]])`）
  - `ReadAloudScript.learningLines(word:example:)` / `learningPrefetchLines(for:)`、`SessionRunner.upcomingWords(limit:)` を足した
  - `SessionView`（提示カード・英→日とリスニングの出題時・回答後・締め・閉じる）、`QuizCardView` のリスニングの「もう一度聞く」、`SpeakButton` を `GeminiReadAloudSpeaker.quiz` に置き換えた。単語詳細は閉じたら止める。グループ詳細を開いたら「学習する」の最初の 2 語を先読みする
  - `SpeechService` と `SpeechServiceTests` を消した。DebugSeed の `session` / `session-new` / `group-learn` / `group-drill` も偽のサーバーの音で鳴らす
- Swift Testing 307 件すべて通過・SwiftLint 警告 0
- シミュレータ（DebugSeed・偽のサーバーの音）で、`session-new` の提示カード（単語 → 例文）、`session` の英→日の出題時（単語）、`group-learn` の最初のカードが Gemini の声（偽の音）で鳴り、内蔵の声に落ちていないことをログで確かめた
  - シミュレータでタップできる道具が無いため、2 枚目以降のカード・回答後・スピーカーのボタンは画面を通しては確かめていない（テストで確かめた範囲のみ）。本物のサーバーでの待ち時間とあわせて、親プランの Phase 6（実機確認）で確かめる
