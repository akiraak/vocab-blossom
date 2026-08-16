# 出題順をランダムにする

## 目的・背景

新規学習の単語が毎回 `a.m.` → `about` → `above` … と ABC 順で出てくる。

原因は 2 つ。

1. `WordStore.newWordPool(level:)` がデッキの並び（＝ CEFR-J の ABC 順 = ID 順）をそのまま返している
2. `SessionBuilder.build` の復習が「期限 → 同着は ID 順」で並ぶため、同じ日に期限が来た語（＝ほとんど）が ABC 順に出る

どちらも「ランダムに並べる」で直すが、単純に毎回 `shuffled()` すると別の問題が出る。

- ホームの「今日の学習」と、実際にセッションで出る語がずれる（`Dashboard.summary` は View の再描画のたびに走る）
- セッションを中断して開き直すと、残りの新規語が別の語に入れ替わる
- 既知語のまとめ登録画面（`KnownWordsPicker`）はプールをページ分割しているので、順番が変わるとページの中身が毎回変わる

そこで **並びは変えるが、同じ端末では毎回同じ結果になる（＝決定的な）シャッフル** にする。

## 対応方針

### 1. `ShuffleOrder`（新規: `ios/VocabBlossom/Core/ShuffleOrder.swift`）

単語 ID と種（seed）から並び順のキーを作り、そのキー順に並べ替える値型。

- `key(_ id: String) -> UInt64`: FNV-1a で ID をハッシュし、seed と混ぜて splitmix64 で撹拌する
  （Swift の `hashValue` はプロセスごとに変わるので使わない）
- `shuffled(_:id:)`: キー順に並べ替える。キー同着は ID 順で安定させる
- `static let install`: 端末ごとの種。`UserDefaults` に無ければ乱数で作って保存する
  → 入れ直すまで並びは変わらず、ユーザーごとには違う並びになる

### 2. `WordStore.newWordPool(level:order:)`

レベル内の語を丸ごとシャッフルして返す。

熟語を 10 語ごとに 1 つ差し込んでいた既存ロジックは削除する。これは「熟語デッキが ID 順で
後ろに固まるので何百語も進まないと熟語に出会えない」問題への対処で、全体をシャッフルすれば
熟語も自然に散らばるため（A1 は 1,012 語 : 100 熟語なので平均 11 語に 1 つ）。
「必ず 10 語に 1 つ」という保証は無くなる。

### 3. `SessionBuilder.build`

- 期限順（古い超過から）で選ぶルールは維持する。ただし**同着の並び替えを ID 順からシャッフル順に変える**
  （上限で打ち切られる日に、いつも ABC 順で先頭の語ばかり選ばれるのを避ける）
- 選んだあとの**出題順はシャッフルする**（毎日同じ並びで覚えてしまうのを避ける）
- `SessionBuilder.Input` / `Dashboard.Input` に `order: ShuffleOrder = .install` を足す（テストで固定できるように）

## 影響範囲

| 箇所 | 影響 |
|---|---|
| `Core/ShuffleOrder.swift` | 新規 |
| `Core/WordStore.swift` | `newWordPool` の並び。熟語の均等混ぜを削除 |
| `Core/SessionBuilder.swift` | 復習の同着並び・出題順 |
| `Core/Dashboard.swift` | `Input` に `order` を追加して素通し |
| `Features/KnownWords/KnownWordsPicker.swift` | 変更なし（プールの順に追従する） |
| `App/DebugSeed.swift` | 変更なし（デフォルト引数） |
| 保存済みの学習データ | 影響なし（進捗は wordId 単位で、並びに依存しない） |

## テスト方針

- `ShuffleOrderTests`（新規）
  - 同じ seed なら何度並べても同じ順、違う seed なら違う順
  - 元の要素が過不足なく残る（順列であること）
  - ABC 順（入力順）とは違う並びになる
- `WordStoreTests`: `newWordPool` がレベル内の語の順列であること・ID 順ではないこと
- `SessionBuilderTests`: 「期限超過の古い順に出す」を「古い順に**選ぶ**（出題順は問わない）」に書き換え、
  上限で打ち切るときに古い方が残ることを検証する。`newWordPoolInterleavesPhrases` は
  「熟語も新規学習プールに混ざる」テストに置き換える
- `xcodebuild test` と `swiftlint`（警告 0）を通す
