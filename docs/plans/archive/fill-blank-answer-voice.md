# 穴埋めの回答後の読み上げを Gemini の声にし、出題の文章を読む

## 目的・背景

穴埋めに答えたあと、今は OS 内蔵の声で「単語 → 単語カードの例文」を読んでいる（`SessionView.feedbackAfterAnswer`）。
これを次のように変える（2026-11-04 ユーザーの依頼）。

- 声: グループの読み上げと同じ Gemini TTS の声（Chobi / Naruko）にする
- 読む文: 「単語 → **出題した文章**」にする。AI で作った文章で出したときはその全文、例文で出したときは例文
  （例文で出したときは今と同じ文になる）

穴埋めは、手がかりの入った 2〜3 文の文章で出す（docs/plans/archive/fill-blank-passages.md）。
答えたあとにその文章を声で聞くと、空欄に入った語が文の中でどう使われるかが耳からも入る。

## 対応方針

### 範囲

- 対象は**穴埋めの問題だけ**（グループの穴埋めモードも、ふだんの学習で穴埋めになった問題も）。
  英→日・日→英・リスニングの回答後と、提示カードの読み上げは今のまま（OS 内蔵の声）
- 回答後の「もう一度聞く」ボタンを穴埋めの答えの欄に置き、同じ内容（単語 → 出題の文章）を Gemini の声で読む。
  単語カードの中の読み上げボタン（`SpeakButton`。単語 → 単語カードの例文・内蔵の声）はそのまま

### 読む内容

- `ReadAloudScript.fillBlankAnswerLines(for: Quiz)`（純粋関数）: 単語の行 + 出題の文章を 1 文ずつに分けた行（種類は `.example`）
  - 文章は `quiz.passage?.text`、無ければ `quiz.sense.example`（出題した意味の例文）
  - 1 文ずつに分ける理由: サーバーの 1 回の文字数の上限（300 字）を超えないため。文と文の間は 0.25 秒あく（グループの読み上げと同じ）
  - 分け方: 「. ! ?」のあとの空白で切る（A1〜A2 の文章なので略語はほぼ出ない）
- 300 字を超える文は、サーバーへ頼まずにその文だけ内蔵の声で読む
  （頼むと 400 になり、「サーバーが失敗した」扱いで 30 秒間すべて内蔵の声になってしまうため）

### 声を出す部分: グループの読み上げの仕組みを使い回す

`GeminiReadAloudSpeaker`（Gemini の音声を取る・端末に残す・取れない文は内蔵の声で読む）をそのまま使う。
ただし、グループの読み上げとは音声セッションの使い方が違うので、もう 1 つインスタンスを作る。

- `GeminiReadAloudSpeaker` と `ReadAloudSpeechEngine` に、音声セッションの使い道（`LearningAudioSession.Purpose`）を渡せるようにする
  - グループの読み上げ（今の `shared`）: `.readAloud`（ほかのアプリの音を止める）
  - 穴埋めの回答後（新しく `quiz`）: `.learning`（ほかのアプリの音を小さくするだけ。効果音・提示カードの読み上げと同じ）
- 読む人は、グループの読み上げと同じく Chobi / Naruko からランダム（3 回続けて同じ人にしない）。1 問の中は同じ人
- 声のモデルは設定画面で選んだもの（今の仕組みのまま）。音声は端末に残すので、同じ文章は 2 回目からすぐ鳴る
- アプリ起動時に `quiz` にもサーバーの取り先（`fetcher`）を入れる。サーバーの設定が無ければすべて内蔵の声で読む

#### 音声セッションの無効化とぶつからないようにする

`GeminiReadAloudSpeaker.speak` / `ReadAloudSpeechEngine.speak` は、読み始めるときに `SpeechService.shared.stop()` を呼んでいる。
`stop()` は 0.4 秒後に音声セッションを無効化するので、`.learning` で鳴らしている Gemini の音声が途中で切れてしまう
（グループの読み上げは「読み上げ中は学習側から無効化しない」決まりで守られていた）。

- `SpeechService` に「読み上げを止めるだけで、無効化はしない（予定していた無効化も取り消す）」メソッドを足し、2 つの `speak` はそちらを呼ぶ。
  グループの読み上げでは、もともと無効化が効かない場面なので動きは変わらない
- 穴埋めの読み上げでは無効化しない。セッションを閉じたとき（今の `SpeechService.shared.stop()`）にまとめて無効化される

### 待ち時間を減らす: 出題したときに音声を取っておく

Gemini の音声は 1 文で数秒かかる。答えてから取りに行くと、効果音のあと少し待つことになる。

- 穴埋めの問題を出したとき（`SessionView.speakIfNeeded`）に、その問題の読む内容の音声を取りに行く（読む予定の人の分だけ）。
  考えている間に取り終えるので、答えたらすぐ鳴る
- `GeminiReadAloudSpeaker` に、読む予定の人の分だけ取る `prefetch` を足す（今の `warmUp` と同じ動き。`warmUp` もこれを使う）
- 答えた時点で取り終えていなければ、取り終えるのを待って鳴らす（取れなければ内蔵の声）

### 止めるとき

- 「次へ」で次の問題へ進んだ・セッションを閉じたら、読み上げを止める（今の `SpeechService` と同じ）
- 効果音のあと 0.5 秒待ってから読む、は今のまま
- 設定の「音声」がオフなら読まない・取りにも行かない

## Phase

### Phase 1: 読む内容と声を出す部分

- `ReadAloudScript.fillBlankAnswerLines(for:)`・文の分け方
- `LearningAudioSession.Purpose` を `GeminiReadAloudSpeaker` / `ReadAloudSpeechEngine` に渡せるようにし、`quiz` インスタンスを作る
- `SpeechService` の「無効化しない止め方」、300 字を超える文はサーバーへ頼まない、`prefetch`
- テスト（Swift Testing）

### Phase 2: 穴埋めの画面につなぐ

- `SessionView`: 穴埋めの回答後は `quiz` で読む。出題したときに `prefetch`。次へ・閉じるで止める
- `QuizCardView`: 穴埋めの答えの欄に「もう一度聞く」ボタン
- `VocabBlossomApp`: `quiz` にも `fetcher` を入れる（DEBUG の偽物も）
- シミュレータで確認（偽物の声・サーバーなし）

#### Phase 1・2 の結果（2026-11-04）

- `ReadAloudScript.fillBlankAnswerLines(for:)`・`sentences(in:)`（ReadAloud.swift）
- `ReadAloudSpeechEngine` / `GeminiReadAloudSpeaker` に音声セッションの使い道を渡せるようにし、`quiz` インスタンスを足した
  （`ReadAloudSpeechEngine.quiz` の割り込みの知らせは `.readAloud` のときだけ出す）
- `SpeechService.interrupt()`（止めるだけで無効化しない）。2 つの `speak` は `stop()` の代わりにこれを呼ぶ
- `GeminiReadAloudSpeaker.prefetch(_:)`（読む予定の人の分だけ。`warmUp` もこれを使う）、300 字を超える文はサーバーへ頼まない
- `SessionView`: 穴埋めの回答後は `GeminiReadAloudSpeaker.quiz` で読む、出題したときに `prefetch`、次の問題へ進む・閉じるで止める。
  `QuizCardView`: 穴埋めの答えの欄の「正解！／おしい！」の右に読み上げボタン（`onReplay`）
- `VocabBlossomApp`: `quiz` にも `fetcher`。DEBUG の `group-fill-blank` / `group-read-aloud` では偽物の声
- Swift Testing 271 件成功（追加: 読む文 4 件・`prefetch`・長すぎる文）、SwiftLint 警告 0
- シミュレータ（`group-fill-blank`・偽物の声）: 出題画面が出て、その問題の「単語・出題の文」の音声が 1 人分だけ端末に残ることを確認。
  答えたあとの再生とボタンはシミュレータで押せないので実機で見る

### Phase 3: 実機確認（2026-11-04 問題なし）

- 答えたらすぐ Gemini の声で「単語 → 出題の文章」が鳴る（文章で出した問題・例文で出した問題）
- 効果音と重ならない、次へで止まる、もう一度聞くで読み直す
- オフラインでは内蔵の声で読む
- ほかのアプリの音楽が小さくなり、セッションを閉じたら戻る

## 影響範囲

- iOS: `ReadAloud.swift`・`GeminiReadAloudSpeaker.swift`・`ReadAloudSpeechEngine.swift`・`SpeechService.swift`・
  `SessionView.swift`・`QuizCardView.swift`・`VocabBlossomApp.swift`（＋テスト）
- グループの読み上げ: 音声セッションの使い道を引数にする・`SpeechService` の止め方を変える。動きは変えない（テストと実機で確認）
- サーバー: 変えない（`POST /api/speech` をそのまま使う）。穴埋め 1 問で 3〜4 回呼ぶ（単語 1 + 文章 2〜3 文）。
  端末に残すので同じ問題は 2 回目から呼ばない。回数制限（10 分に 600 回）には余裕がある

## テスト方針

- Swift Testing:
  - `fillBlankAnswerLines`: 文章あり（全文を文ごとに）・文章なし（例文）・意味が複数ある語は出題した意味の例文・空の例文
  - 文の分け方（. ! ? で分ける・空白の整理）
  - `GeminiReadAloudSpeaker`: `prefetch` は読む予定の人の分だけ取る・300 字を超える文はサーバーへ頼まずに内蔵の声で読む・
    使い道（`.learning`）を渡しても読む順・止め方は変わらない
- `xcodebuild test` と `swiftlint`（警告 0）
- 実機: Phase 3
