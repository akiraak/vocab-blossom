# 穴埋めの文章を順番に出す

## 目的・背景

穴埋め用の文章は 1 語（1 つの意味）につき 3 パターンある（`PASSAGES_PER_WORD = 3`）。
今は問題を作るたびに、空欄にできる文章（すべての意味の分）から**ランダムに 1 つ**選んでいる（`QuizBuilder.make(for:type:)`）。
どれを出したかを覚えていないので、前回と同じ文章が続けて出ることがある。

→ 前回と違う文章を、1 → 2 → 3 → 1 … の順に出す。

## 対応方針

- **出した文章を覚える `PassageHistory`**（`Core/Passages.swift`）
  - 文章の鍵（`Passages.key`。綴り・品詞・意味）ごとに、最後に出した文章の位置（0〜2）を持つ
  - Application Support の `passage-history.json` に保存する。`PassageCache` と同じく同期・バックアップには入れない（消えても 1 つ目から出し直すだけ）
  - `fileURL: nil` で保存しない（テスト用）
- **選び方**（`QuizBuilder`）
  - 意味が複数ある語は、空欄にできる文章がある意味からランダムに 1 つ選ぶ（今は文章の数で重みが付いていたが、意味ごとに同じ確率にする）
  - その意味の文章のうち、前回出した位置の次から順に見て、最初に空欄にできるものを出す（最後の次は最初に戻る）
  - 履歴が無ければ 1 つ目（空欄にできる最初のもの）
  - 文章が無い・空欄にできないときに例文を使うのは今のまま
- **覚えるタイミング**: 回答したとき（`SessionRunner.answer`）
  - 穴埋めモードは問題を全部先に作るので、作った時点で覚えると途中で閉じた語の文章が飛ばされる
  - `Quiz` に出した文章の位置（`passageIndex`）を持たせ、回答したら `PassageHistory` に記録する
  - 間違えた問題の再出題で同じ問題をもう一度答えても、同じ位置を記録し直すだけ
- 穴埋めモード・毎日の学習・ドリルのどれも `QuizBuilder` を通るので、全部に効く

## 影響範囲

- `ios/VocabBlossom/Core/Passages.swift`（`PassageHistory` を足す）
- `ios/VocabBlossom/Core/QuizBuilder.swift`（`Quiz.passageIndex`、選び方）
- `ios/VocabBlossom/Features/Session/SessionRunner.swift`（回答時に記録）
- `ios/VocabBlossom/Features/Session/SessionView.swift`・`FillBlankSessionView.swift`（環境から `PassageHistory` を渡す）
- サーバーは変えない

## テスト方針

- Swift Testing
  - `PassageHistory`: 記録・保存して開き直すと残る
  - `QuizBuilder`: 履歴が無ければ 1 つ目、記録するたびに 2 つ目 → 3 つ目 → 1 つ目と進む。空欄にできない文章は飛ばす
  - `SessionRunner`: 回答すると出した文章の位置が記録される
- SwiftLint 警告 0
- シミュレータで穴埋めモードを 2 回やり、2 回目は別の文章が出ること
