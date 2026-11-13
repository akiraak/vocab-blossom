# 穴埋めで単語をキー入力するモード

## 目的・背景

今の穴埋め（グループ詳細の「穴埋め」）は、文章の空欄に入る語を 4 択から選ぶ。
選択肢があると、綴りを覚えていなくても見て選べてしまう。

→ 空欄に入る語を**キーボードで打って答える**モードを足す。綴りまで思い出す練習にする。

問題は**始めるたびに作り直す**。端末やサーバーに文章がある語も AI で新しい文章を作り、前と同じ文章が出ないようにする。
今の 4 択の穴埋め（文章の無い語の分だけ作って 3 パターンを順に使い回している）も、同じく毎回作り直すようにする。

## 対応方針

### 入口

- グループ詳細のボタンは今の「穴埋め」のまま増やさない。押したあと、最初の画面で**答え方を選ぶ**（「4 択で選ぶ」「キーボードで入力」）
  - 選んでから文章を作り始める（同じフルスクリーンの中で 選ぶ → 作る → 出題 と切り替える）
- どちらも進捗（SRS）・`AnswerLog` は動かさない練習。回答は `GroupAnswerLog` に残す（入力の入口は `fillBlankTyping` を足す）
- 毎日の学習・「学習する」・ドリルの穴埋めは 4 択のまま（端末にある文章を使う。作り直さない）

### 問題を作る（始めるとき）

今の `FillBlankSessionView` の最初に答え方を選ぶ画面を足し、4 択・入力のどちらも同じ流れで作る。

1. グループの**全語・全意味**の文章をサーバーで作り直す（`PassagePreparation`・`PassagePreparationView`。作る間の画面は今のまま）
2. 全語の問題を組み立てる（`QuizBuilder`。並びはシャッフル）
3. 4 択は、今と同じく選択肢を AI で判定してから出す（`FillBlankCheck`）。
   入力は**選択肢を作らない**ので、判定は飛ばしてすぐ出題する

#### 作り直し（サーバー `POST /api/passages`）

- リクエストに `refresh: true` を足す。付いていたら、ためてある文章があっても AI で作る
- **前の文章と違うものにする**: サーバーにためてある前の 3 パターンを AI に渡し、「これと違う場面・文にする」と指示する。
  返ってきた文章が前のどれかと同じなら検証で落とす（今の作り直し 1 回の中で作り直す）
- 作れたら `word_passages` を新しい 3 パターンで上書きする。作れなかった語は前の文章を消さずに空で返す
- `refresh` が無いリクエストは今のまま（ためてあれば AI を呼ばない）。iOS からは使わなくなるが、古い版のアプリのために残す

#### 端末（iOS）

- 4 択・入力のどちらも、文章のある・無しにかかわらず全語を `refresh` 付きで送る（3 語ずつ・3 本並べるのは今のまま）
- 返ってきた文章で `passages.json` を上書きする
- 1 語につき 3 パターン作るが、1 回で使うのは 1 つ。残りは毎日の学習・ドリルの穴埋めと、作り直せなかったときの控えになる
- **作り直せなかった語**（通信できない・AI の失敗・回数制限）は、端末にある前の文章を出す（`PassageHistory` で前回の次のもの）。
  それも無ければ例文。どの意味でも空欄にできない語は出さない（今の `canFillBlank` と同じ）
- すべて失敗したときは、今の「もう一度」「例文で始める」の画面を出す（文言は「今ある文章で始める」に変える）
- サーバーの設定が無いときは作り直さず、今ある文章・例文ですぐ始める
- **待ち時間**: 毎回全語を作るので、始めるたびに待つ（今は 3 語で 1 回の AI 呼び出し。20 語なら 7 回を 3 本並べる）。
  4 択はそのあと選択肢の判定も待つ。今は 2 回目からすぐ始まっていたのが、毎回待つようになる。
  Phase 2 で実際の時間を測り、長すぎれば 1 回に作るパターン数を減らすなどを考える

### 問題の中身（`Quiz`）

- 出題形式（`QuizType`）は `.fillBlank` のまま。統計・`AnswerLog`・バックアップの形式に触れないため
- `Quiz` に答え方 `input`（`.choice` / `.typing`）を足す
- 入力の問題は `choices` を空にし、正解の綴り `typedAnswer` を持つ
  - 正解は**文中で空欄にした形だけ**（例: 見出し語 adapt、文中は adapted → `adapted`）。
    見出し語（`adapt`）を打っても、文中の形と違えば不正解
  - 「either … or …」のように空欄が 2 か所の語は、空白で区切って打つ（`either or`）
- `QuizBuilder.blank` を、空欄にした文と一緒に**空欄にした元の綴り**も返す形にする

### 判定

`Quiz.isCorrect(typed:)`。打った文字と `typedAnswer` を、そろえてから比べる。

- 前後の空白を除く・連続する空白は 1 つに・大文字小文字を区別しない
- 「’」と「'」は同じに扱う
- 綴りの違い・活用の違いは不正解（1 文字違いを許さない。綴りを覚えるモードなので）
- 「わからない」は不正解として答えを見せる

### 進行（`SessionRunner`）

- `answer(text:)` を足す。記録・再出題・`PassageHistory` は `answer(choiceIndex:)` と同じ処理を通す
- 回答済みかは `selectedIndex` だけで見ているので、入力の回答（`typedAnswer`）も含めて見る `isAnswered` にまとめる
- 間違えた問題は、今と同じく最後にもう一度出す（同じ問題・2 回まで）

### 画面（`QuizCardView`）

- 問題文: 空欄にした文章だけ。**ヒント（意味・頭文字・文字数）は出さない**（まずこれで作って、使ってみて考える）
- 入力欄と「わからない」「答える」はスクロールの外（下）に置く。キーボードが出ても長い文章に押し出されないように
- 入力欄: iOS の入力の補完を効かせない（答えが候補に出たり、打ち間違いが勝手に直ったりしないように）。問題が出たらフォーカスする
  - 自動修正・予測変換の候補・スペルチェック・先頭の大文字化・インライン予測を切る
    （`autocorrectionDisabled`・`textInputAutocapitalization(.never)`・`UITextInputTraits` の `spellCheckingType = .no`・`inlinePredictionType = .no`）
  - 英字キーボード（`.asciiCapable`）。日本語キーボードの変換候補を出さないため
  - SwiftUI の `TextField` ではスペルチェックとインライン予測を切れないので、`UITextField` を包んだ `TypingAnswerField` を使う。実機で確かめる
- 「答える」（空なら押せない。キーボードの確定でも答える）と「わからない」
- 答えたあと: キーボードを閉じ、打った綴りと正誤・正解の綴り・全文と和訳・単語カードを見せて「次へ」
  - 見出し語を打って不正解になったとき（adapt / adapted）は「この文では adapted の形」と添える
- 読み上げ・効果音は 4 択の穴埋めと同じ（答えたあと 単語 → 出題の文章）

## 影響範囲

- `ios/VocabBlossom/Core/QuizBuilder.swift`（`Quiz.input`・`typedAnswer`・判定、`blank` の返り値、入力の問題の組み立て）
- `ios/VocabBlossom/Features/Session/SessionRunner.swift`（`answer(text:)`、回答済みの見方）
- `ios/VocabBlossom/Features/Session/SessionView.swift`（回答後のフィードバックのきっかけ、入力の回答を渡す）
- `ios/VocabBlossom/Features/Session/QuizCardView.swift`（入力欄と答えたあとの表示）
- `ios/VocabBlossom/Features/Session/FillBlankSessionView.swift`（答え方を選ぶ画面、全語の作り直し、入力は判定を飛ばす）
- `ios/VocabBlossom/Features/Groups/GroupDetailView.swift`（ボタンの説明のコメントだけ）
- `ios/VocabBlossom/Models/GroupAnswerLog.swift`（`GroupAnswerSource.fillBlankTyping`。バックアップにもこの値が入る）
- `ios/VocabBlossom/App/DebugSeed.swift`（画面確認用の入口）
- `ios/VocabBlossom/Core/Sync/PassageClient.swift`（`refresh` を送る）
- `ios/VocabBlossom/Core/PassagePreparation.swift`（全語を作り直す一覧、作り直せなかった語の扱い）
- `ios/VocabBlossom/Features/Session/PassagePreparationView.swift`（失敗したときの文言）
- `server/src/ai/passages.ts`（`refresh`、前の文章と同じなら落とす検証、上書き）
- `server/src/ai/claude-passages.ts`（前の文章を渡して違うものを作らせる指示）
- `docs/specs/app-concept.md`（グループのモードの説明）
- サーバーは g3plus へのデプロイが要る（DB の形は変えない）

## テスト方針

- Vitest（サーバー）
  - `refresh` 付きは、ためてある文章があっても AI を呼び、新しい文章で上書きする。AI には前の文章が渡る
  - 前と同じ文章を返したら落として作り直す。作れなければ前の文章を残し、その語は空で返す
  - `refresh` 無しは今のまま（ためてあれば AI を呼ばない）
- Swift Testing
  - `PassagePreparation`: 文章のある語も全部送り、返った文章でキャッシュを上書きする。失敗した語は前の文章が残る
  - `QuizBuilder`: 入力の問題は選択肢が空で、正解の綴りは文中で空欄にした形。活用形・熟語・「either … or …」
  - `Quiz.isCorrect(typed:)`: 大文字小文字・前後と連続の空白・アポストロフィの違いは正解、綴り違い・活用違い（見出し語）・空は不正解
  - `SessionRunner`: 入力で答えると回答数・正解数・`GroupAnswerLog`・`PassageHistory` が残る。間違えると再出題される。同じ問題への 2 回目の回答は無視
  - バックアップ: `fillBlankTyping` の記録を書き出して読み込める
- SwiftLint 警告 0
- シミュレータ: 答え方を選ぶ → 4 択・入力をそれぞれ通しでやる（正解・不正解・わからない・再出題・締め）。
  2 回やって文章が変わること。キーボードで入力欄や「次へ」が隠れないこと
- 実機: 候補の帯・自動修正・インライン予測が出ないこと、打ちやすさ、待ち時間

## 進め方

### Phase 1: 問題と判定（Core）

- `Quiz.input`・`typedAnswer`・`isCorrect(typed:)`
- `QuizBuilder.blank` が空欄にした綴りも返す。入力の問題を組み立てる
- テスト

### Phase 2: 文章の作り直し（サーバー）

- `POST /api/passages` に `refresh`。前の文章を AI に渡し、同じ文章を検証で落とす
- テスト。ローカルで数語を作り直して、文章が変わること・待ち時間を確かめる
- g3plus へデプロイ（指示があってから）

### Phase 3: 進行（SessionRunner）

- `answer(text:)`、回答済みの見方をまとめる
- `GroupAnswerSource.fillBlankTyping`
- テスト

### Phase 4: 画面

- `QuizCardView` の入力欄（補完を切る）と答えたあとの表示
- `FillBlankSessionView` に答え方を選ぶ画面。4 択・入力とも全語を作り直す（`PassageClient`・`PassagePreparation` の `refresh`）。入力は判定を飛ばす
- `DebugSeed`
- シミュレータで確認

### Phase 5: 実機確認と後片付け

- iPhone で確認（ユーザー）
- `docs/specs/app-concept.md` を更新、`DONE.md` へ移動、プランを archive へ

## 決めたこと

2026-11-12 に決めた。

- **問題の生成**: 始めるたびに、すでにある文章も作り直す。同じ文章が出ないようにするため。4 択の穴埋めも同じ
- **入口**: 「穴埋め」を押したあとに 4 択か入力かを選ぶ
- **見出し語を打ったとき**: 文中の形と違えば不正解。iOS の入力の補完も効かせない
- **ヒント**: 何も出さない（文章だけ）で、とりあえず実装する

## 実装の記録（2026-11-12）

- Phase 1〜4 のコードを入れた。Vitest 265 件・型チェック OK、Swift Testing 330 件・SwiftLint 警告 0
- シミュレータ（偽のサーバー）で、答え方を選ぶ画面 → 作る画面 → 入力の問題が出るところまで見た。
  シミュレータでは文字を打てなかったので、打って答えたあとの画面（正誤・正解の綴り）は見ていない
- 残り
  - サーバーを g3plus へデプロイする（まだ。デプロイするまで、本番は `refresh` を無視して前と同じ文章を返す）
  - 実機で確認: 補完が出ないこと、打って答えたあとの画面、待ち時間
  - ヒントを出さないので、文章だけでは語が決まらない問題がどのくらいあるかを使って確かめる
  - `docs/specs/app-concept.md` の更新（後片付けで）
