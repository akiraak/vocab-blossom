# グループの問題をこなした記録を残す

## 目的・背景

グループの穴埋め・ドリルの成績は今どこにも残らない（2026-11-06 に調査）。

- ドリル（`SessionRunner` の `mode == .drill`）は `WordProgress` も `AnswerLog` も書かず、`stats` はメモリの上だけで、締めの画面を閉じると消える
- 統計画面の「穴埋め」の正答率は `AnswerLog` から数えていて、いつもの学習のステージ 3 の穴埋めしか入らない
- サーバーにも回答の記録は無い（同期するのはグループ・マイ単語・削除の記録だけ）

グループの問題をどれだけこなしたかを、グループ一覧で見られるようにする。

- **まずはシンプルに、回答した回数だけ**をグループ一覧に出す（Phase 1）
- できれば**達成度**も出す（Phase 2）

## 対応方針

### 1. 記録の置き場所: 新しいモデル `GroupAnswerLog`（1 回答 1 行）

```swift
@Model
final class GroupAnswerLog {
    var groupId: UUID       // WordGroup.id（サーバーと同じ ID なので、同期で作り直されても変わらない）
    var wordId: String
    var answeredAt: Date
    var correct: Bool
    var quizType: QuizType  // 穴埋め・英→日など
    var source: Source      // learning（グループの「学習する」）/ drill / fillBlank
    var kind: AnswerKind    // review / new / requeue（再出題）
}
```

- **回数だけでなく 1 回答ずつ残す**: 回数は行の数で出せる。あとから達成度（語ごとの正誤）・日ごとの回数・形式ごとの正答率を足すときに、記録の形を変えずに済む。
  1 日に数十〜数百行なので、端末の負担にはならない
- **`AnswerLog` は使わない**: 統計・ストリーク・ダッシュボードが全部 `AnswerLog` から数えているので、ドリルの回答を混ぜると、
  全部の集計で除外が要る（漏れると「ドリルで SRS が進んだように見える」）。別のモデルにして、今の集計には触らない
- 回答するたびに書く（いつもの学習と同じ。途中で閉じても、答えた分は残る）
- SwiftData にモデルを 1 つ足すだけなので、マイグレーションは自動（`VersionedSchema` は使っていない）

### 2. 記録する場面

グループ詳細から始める 3 つ（「学習する」「ドリル」「穴埋め」）で記録する（決めること 1）。

- `SessionRunner` に「どのグループのどの入口から始めたか」（`GroupContext?`）を渡し、`answer()` で `GroupAnswerLog` を足す。
  nil（毎日の学習）なら書かない
- `SessionView` の 3 つの init と `FillBlankSessionView` に、グループ ID を渡す口を足す
- 「学習する」の回答は今までどおり `AnswerLog` にも書く（SRS の記録）。`GroupAnswerLog` には「グループでこなした分」として別に残る
- 再出題（`kind == .requeue`）も 1 回の回答として数える（答えた回数をそのまま出す）

### 3. グループ一覧に出す（Phase 1）

`GroupRow` の 2 行目に回数を足す。

```
📁 11-05                              復習 3
   9 語・学習済み 3 語・回答 42 回
```

- グループ一覧で `@Query` で `GroupAnswerLog` を読み、`groupId` ごとに数える（一覧を開くたびに全件読むが、
  数千行までなら問題ない。重くなったらグループに回数を持たせる）
- 0 回のときは「回答 0 回」を出さない（今の表示のまま）
- グループ詳細の上の数（単語・学習済み・開花）の並びにも「回答」を足す

### 4. 達成度（Phase 2）

案: **「グループの語のうち、最後に答えたときに正解だった語」の割合**（決めること 2）。

- 語ごとに `GroupAnswerLog` の最新の 1 行を見て、正解なら達成。答えたことが無い語・最後に間違えた語は未達成
- 全部の語を一度は正解し、最後に間違えていなければ 100%。間違えると下がるので、「今のグループの仕上がり」が分かる
- グループから外した語は数えない（今の `wordIds` だけで数える）
- 一覧の行の右か 2 行目に `達成 67%`、または細いバーで出す。詳細にはバーと「6 / 9 語」を出す

ほかの案:

- SRS のステージを使う（学習済み・開花の割合）: もう「学習済み N 語」「開花」として出ている。ドリル・穴埋めをこなしても変わらない
- 回数の目標（例: 全語を 3 回ずつ答える）に対する割合: 分かりやすいが、目標の決め方が要る

### 5. 消すとき・同期・バックアップ

- **グループを消したら、そのグループの `GroupAnswerLog` も消す**（`GroupEditor.delete`。同期で届いたグループの削除も同じ）
- **マイ単語を消したら、その語の `GroupAnswerLog` も消す**（`GroupEditor.purgeCustomWord` が今 `AnswerLog` を消しているのと同じ）
- **同期はしない**: 利用は iPhone 1 台で、回答の記録はサーバーに送っていない（`AnswerLog` も送っていない）
- **バックアップには入れる**（Phase 3）: `BackupArchive` を version 4 にし、`groupAnswers` を足す（v3 以前のファイルには無いので空として読む）。
  機種変更・入れ直しで消えないようにするため

## Phase

### Phase 1: 回答を残して、グループ一覧に回数を出す

- `GroupAnswerLog` を足し、`AppModel.schema` に入れる
- `SessionRunner` に `GroupContext` を渡し、`answer()` で記録する。グループ詳細の 3 つの入口からグループ ID を渡す
- グループ・マイ単語を消すとき、記録も消す
- `GroupRow` とグループ詳細に回数を出す

### Phase 2: 達成度を出す

- `GroupStudy` に達成度を出す純粋関数（語ごとの最新の正誤 → 達成した語の数）を足す
- 一覧の行と詳細に出す

### Phase 3: バックアップに入れる

- `BackupArchive` version 4。書き出し・読み込み・古い版の読み込みのテスト

### Phase 4: 実機確認

- 穴埋め・ドリル・学習をこなして一覧の回数・達成度が増える、途中で閉じても答えた分は残る、アプリを入れ直さずに更新しても今のデータが消えない（SwiftData のモデル追加）

## 影響範囲

- iOS: `Models/`（`GroupAnswerLog` を追加）、`App/VocabBlossomApp.swift`（`AppModel.schema`）、`Features/Session/SessionRunner.swift`・`SessionView.swift`・`FillBlankSessionView.swift`、
  `Features/Groups/GroupListView.swift`・`GroupDetailView.swift`、`Core/GroupStudy.swift`、`Core/GroupEditor.swift`、`Core/BackupArchive.swift`
- サーバー: 変えない
- 今の SRS・`AnswerLog`・統計画面・ストリークは変えない
- 注意: `SessionRunner.swift` に、つなぎ言葉の穴埋めタスクのコミットしていない変更がある。混ざらないよう、そちらをコミットしてから始める

## テスト方針

- Swift Testing:
  - `SessionRunner`: グループの指定があれば、ドリル・組み立て済みの問題・学習の各モードで 1 回答 1 行を書く（正誤・形式・再出題）。指定が無ければ書かない。学習では `AnswerLog` も今までどおり書く
  - 回数・達成度の集計（最後の回答で決まる・答えていない語は未達成・外した語は数えない・空のグループ）
  - グループ・マイ単語を消すと記録も消える
  - バックアップ: v4 の書き出しと読み込み、v3 のファイルを読める
- シミュレータ: グループ一覧・詳細の表示（回数 0・あり、達成度 0%・100%）
- 実機: Phase 4

## 結果

### 決めたこと（2026-11-06）

案どおり: 「学習する」・ドリル・穴埋めの 3 つとも数える／達成度は最後に答えたときに正解だった語の割合／バックアップに入れる

### Phase 1〜3（2026-11-06）

- `Models/GroupAnswerLog.swift`: `GroupAnswerLog`（1 回答 1 行）・`GroupAnswerSource`（learning / drill / fillBlank）・
  `GroupAnswerContext`（グループ ID と入口）・`GroupAnswerLog.purge(groupId:in:)`。`AppModel.schema` に足した
- `LearningEngine.recordGroupAnswer(_:wordId:correct:quizType:kind:now:)` で書く。`SessionRunner` の 3 つの init に `group: GroupAnswerContext?` を足し、
  `answer()` で、指定があればどのモードでも書く（再出題も 1 回）。`SessionView`・`FillBlankSessionView` を通して、グループ詳細の 3 つの入口から渡す
- 消すとき: `GroupEditor.delete`・同期で届いたグループの削除（`SyncEngine.applyDeletion`）でそのグループの記録を、
  `GroupEditor.purgeCustomWord` でその語の記録を消す
- 集計: `GroupStudy.activity(wordIds:answers:)` → `Activity`（回答数・達成した語・語数・達成度）。
  達成度の % は切り捨て（1 語でも残っていれば 100% にしない）。文言は `GroupActivityText`
- 表示: 一覧の行に、答えたことがあるグループだけ 3 行目「回答 24 回・達成 46%」と細いバー。
  詳細の上の数に「回答 N 回」、その下に達成度のバーと「6 / 13 語（46%）」（答えたことがあるときだけ）
- バックアップ: `BackupArchive` version 4 に `groupAnswers`（v3 以前は空として読む。読み込みは置き換え）
- `DebugSeed` の「小テスト Unit 3」に記録のダミーを入れた（画面確認用）
- Swift Testing 303 件（`GroupAnswerLogTests` 11 件を追加）・SwiftLint 警告 0
- シミュレータ（iPhone 17 Pro）で一覧（回答 24 回・達成 46%、記録の無いグループは今の表示のまま）と詳細の表示を確認

## 決めること

1. **どの回答を数えるか**: グループ詳細の「学習する」の回答も数えるか、ドリルと穴埋めだけにするか（案: 3 つとも数える。グループの問題をこなした量としてまとめて見たいので）
2. **達成度の決め方**: 「最後に答えたときに正解だった語の割合」でよいか（案: これ。ほかの案は上の 4.）
3. **バックアップに入れるか**: Phase 3 をやるか、いったん端末だけにするか（案: やる）

## 実機確認（2026-11-07）

- 実機確認はユーザーが済ませ、2026-11-07 に完了の報告を受けて閉じた
