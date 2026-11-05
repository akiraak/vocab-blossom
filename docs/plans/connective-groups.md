# 接続詞・つなぎの語句をグループに登録する

## 目的・背景

TODO の「接続詞・つなぎの語句で穴埋めが作れるか検証する」の前に、検証に使う語をグループに登録する。
語はユーザーが挙げた 94 個（2026-11-04）。

1 つのグループに 94 語を入れると学習しづらいので、**働き（時・条件・逆接・理由・目的など）ごとに 10 のグループに分ける**（2026-11-04 に案 A に決定）。

- when / if / although / because / so that は、どれも接続詞でも働きが違う（時・条件・逆接・理由・目的）。
  この分け方で、同じ働きの語を並べて覚え、同じ意味で形が違う語（because と because of など）を見比べられるようにする
- 1 グループは 7〜12 語。新規語は 1 日 10 語が既定（`AppSettings.newWordsPerDayChoices`）なので、だいたい 1 回の学習で 1 グループを始められる

穴埋めの文章が作れるかどうかの検証と修正は、このタスクではやらない（TODO の既存項目でやる）。
このタスクの完了条件は「10 グループが iPhone に同期され、各語のカードが表示できる」ところまで。

## 語の一覧（ユーザーが挙げたもの）

in addition, moreover, furthermore, besides, however, on the other hand, nevertheless, consequently, therefore, as a result,
for instance, for example, in addition to, not only … but also …, in order to, to, for, so that, although, even though, though,
in spite of the fact that, in spite of, because, since, due to, due to the fact that, if, unless, even if, when, while, before,
after, during, whether, as long as, provided that, in case, and, but, so, be caused by, because of, as a result of,
for this reason, leads to, also, additionally, similarly, likewise, in contrast, by contrast, whereas, still, yet, despite,
thus, hence, accordingly, otherwise, or, either … or …, neither … nor …, both … and …, even when, even so, only if,
as soon as, once, until, whenever, by the time, ever since, meanwhile, then, afterward, subsequently, finally, in fact,
actually, in other words, that is, specifically, such as, instead, instead of, rather than, overall, in summary,
in conclusion, result in, result from, contribute to

- `leads to` は見出し語の形（原形）にそろえて `lead to` にする（`result in` などと同じ）

## 対応方針

### 1. グループ案（10 グループ・94 語）

★ は単語帳にある語（同梱語。ID をそのまま入れる）、無印はマイ単語として作る語。
※ は単語帳にあるが意味が違うので、つなぎの意味のマイ単語を作る語（下の 2.）。

| # | グループ名 | 語 | 語数 |
|---|---|---|---|
| 1 | つなぎ言葉・時 1 | when※, ★before, ★after, ★while, ★during, ★until, ★then, ★finally | 8 |
| 2 | つなぎ言葉・時 2 | once※, as soon as, whenever, by the time, ever since, meanwhile, afterward, subsequently | 8 |
| 3 | つなぎ言葉・条件 | ★if, unless, even if, only if, as long as, provided that, in case, otherwise, whether, even when | 10 |
| 4 | つなぎ言葉・逆接と対比 1 | but, ★however, ★although, in spite of, still※, on the other hand, in contrast | 7 |
| 5 | つなぎ言葉・逆接と対比 2 | yet※, ★though, even though, despite, in spite of the fact that, nevertheless, even so, by contrast, whereas | 9 |
| 6 | つなぎ言葉・理由と結果 1 | ★because, since※, ★because of, due to, ★so, ★therefore, as a result, for this reason, lead to, result in | 10 |
| 7 | つなぎ言葉・理由と結果 2 | due to the fact that, as a result of, be caused by, result from, thus, hence, consequently, accordingly, contribute to | 9 |
| 8 | つなぎ言葉・目的と選択 | to, in order to, so that, ★for, or, either … or …, neither … nor …, ★instead, ★instead of, rather than | 10 |
| 9 | つなぎ言葉・追加と類似 | and, ★also, ★besides, in addition, in addition to, moreover, furthermore, additionally, not only … but also …, both … and …, similarly, likewise | 12 |
| 10 | つなぎ言葉・例示とまとめ | ★for example, for instance, ★such as, in other words, that is, specifically, ★in fact, ★actually, overall, in summary, in conclusion | 11 |

- 単語帳にある語: 29 語（※の 5 語を除くと 24 語）。マイ単語として作る語: 70 語（※の 5 語を含む）
- 語の多い働き（時・逆接と対比・理由と結果）は 1 と 2 に分ける。1 によく使う語、2 に硬い語・長い語を置く
- グループ名は一覧で並べたときに働きが分かるよう「つなぎ言葉・〇〇」にする。番号は学ぶ順の目安（1 の付くものから）

### 2. 単語帳にあるが、つなぎの意味が入っていない語（※の 5 語）

| 語 | 単語帳の意味 | つなぎとしての意味 |
|---|---|---|
| when（a1-0978・副詞） | いつ | 〜するとき |
| since（a2-0986・前置詞） | 〜以来 | 〜なので |
| once（a1-0620・副詞） | 一度／かつて | いったん〜すると |
| yet（a1-1009・副詞） | まだ／もう | それでも／しかし |
| still（a1-0833・形容詞） | まだ／じっとした | それでも |

単語帳の語のまま入れると、このグループではつなぎの意味を学べない。
そこで**つなぎの意味のマイ単語を同じ綴りで作ってグループに入れる**（案。Phase 1 で確定する）。単語帳の語はそのまま残り、学習の記録も別になる。
単語一覧では同じ綴りが 2 つ並ぶが、4 択で同じ綴りが並ばないことは `QuizBuilder` で保証されている。

ほかの単語帳の語（because・although・however など）は、意味がつなぎの使い方と合っているのでそのまま使う。
for（〜のために／〜の間）・before（〜の前に）も今の意味で使う。

### 3. 同じグループに似た意味の語が入ることへの対処

マイ単語の 4 択の誤答肢は同じグループの語から優先して選ぶ（`QuizBuilder.distractors`）。穴埋めも同じ選択肢を使う。
働きで分けると、however の問題に but・nevertheless が並ぶような「正解が 1 つに決まらない問題」が出る。
このタスクでは次の 2 つで減らし、残りは次の検証タスクで直す。

- **言い換えのきく組は 1 と 2 に分ける**: although / though、in spite of / despite、still / even so・nevertheless、
  because・since / due to the fact that、therefore / thus・hence・consequently、as a result / as a result of など
- **意味に使い方を添えて区別する**: 同じ働きの中で、後ろに来る形（文・名詞・-ing）や置く位置（文頭・文中）を括弧で書く。
  例: because「〜なので（後ろに文）」、because of「〜のせいで（後ろに名詞）」、however「しかしながら（文頭で前の文を受ける）」、
  but「しかし（文と文をつなぐ）」、in addition to「〜に加えて（後ろに名詞）」、moreover「そのうえ（文頭で）」。
  同じ意味で形が違う、という一番大事な点がカードで分かるようにする

それでも同じグループに残る主な組（次の検証タスクで扱う）:

| グループ | 組 |
|---|---|
| 時 1 / 時 2 | while と during、once と as soon as、afterward と subsequently |
| 条件 | if と provided that と as long as、even if と even when |
| 逆接と対比 1 / 2 | but と however、yet と nevertheless と even so、though と even though、by contrast と whereas |
| 理由と結果 1 / 2 | because と since、because of と due to、so と therefore と as a result と for this reason、lead to と result in、thus と hence と consequently と accordingly |
| 目的と選択 | to と in order to と so that、instead of と rather than |
| 追加と類似 | also・besides・in addition・moreover・furthermore・additionally、similarly と likewise |
| 例示とまとめ | for example と for instance と such as、in other words と that is、in fact と actually、overall と in summary と in conclusion |

**次の検証タスクへの引き継ぎ**: 上の組で、4 択・穴埋めの正解が複数になる問題が出るかを実機で確かめ、必要ならアプリ側で直す。
直し方の候補: つなぎ言葉の誤答肢をほかの働きのグループから選ぶ／同じ働きの語を誤答肢にしない（働きを語に持たせる）など。

### 4. マイ単語の中身（意味・例文・訳）

70 語分の `word`・`pos`・`meaning`・`example`・`exampleJa` は、このセッションで下書きを作り、ユーザーが確認してから登録する。

- **品詞**: 1 語の接続詞・副詞はそれぞれ `conjunction` / `adverb`、2 語以上は `phrase`。
  ただし despite は `preposition`、and / but / or / unless / whereas などは `conjunction`
- **意味**: 初学者向けに 1〜2 個。上の 3. のとおり、似た語と区別できるよう使い方を括弧で添える。
  単語帳のどの語とも、作る語どうしでも、意味の文字列が重ならないようにする
- **例文**: 単語帳と同じ基準（3〜12 語、A1〜A2 の語彙、見出し語を 1 回だけ含む）。
  … を含む語（not only … but also … など）は、見出し語の照合（`Inflector.findHeadword`）で見つからない可能性が高い。
  見つからなくても登録はでき、カードは表示される（穴埋めにならないだけ）。直すかどうかは次の検証タスクで決める
- 下書きは `data/groups/connectives.json` に置く（グループ名と、各語の同梱語 ID か、マイ単語の中身）

### 5. 登録のしかた: サーバーで JSON を取り込むスクリプト

70 語を管理画面やアプリから 1 語ずつ作るのは手間がかかり、打ち間違いも起きやすい。
管理画面の処理（`AdminService`）を使って JSON からまとめて取り込むスクリプトを作り、サーバー（g3plus）で 1 回動かす。
サーバーに入ればアプリの同期で iPhone にも届く。

- `server/src/admin/import-groups.ts`（取り込みの処理）と `server/src/import-groups.ts`（CLI。`main.ts` と同じ並び）: JSON を読んで、次を行う
  - グループを作る（`createGroup`）。同じ名前のグループがあれば作らずにそのまま使う（2 回動かしても増えない）
  - 同梱語は ID を足す（`addWords`。入っていれば飛ばす）
  - マイ単語は `upsertCustomWord`（同じ綴りのマイ単語があれば中身を置き換えて ID はそのまま。中身が同じなら触らない）
  - 同梱語の ID が存在しない・入力の誤り（`validateDraft`）は、何も書き込まずにエラーで止める（全体を 1 つのトランザクションにする）
  - 何を作り、何を飛ばしたかを標準出力に出す。`--dry-run` で書き込まずに結果だけ見られるようにする
- スクリプトは `server/src` の下に置く（サーバーのイメージには `server/src` しか入らないため）。
  JSON はイメージに入れず、`docker compose exec -T vocab-blossom node server/src/import-groups.ts < data/groups/connectives.json` で渡す
- 動いているサーバーと同じ DB に書くが、WAL・`busy_timeout` が設定済みなので、同時に書いても待つだけで壊れない

## Phase

### Phase 1: グループ分けとマイ単語の下書き

- ※の 5 語の扱い（マイ単語を作るか）と、`to`・`and`・`or` などの短い語を入れるか（下の「決めること」）を決める
- `data/groups/connectives.json` に 70 語の下書きを作る
- 確認しやすいよう、グループごとの一覧（語・品詞・意味・例文・訳）を表にしてユーザーに見てもらい、直す
- 簡単なチェック（例文の語数・見出し語を含むか・意味の重複）をスクリプトで確認する

#### Phase 1 の途中経過（2026-11-04）

- 決めたこと: ※の 5 語はつなぎの意味のマイ単語を作る。to・and・or なども入れ、穴埋めでの扱いは次の検証タスクで決める
- `data/groups/connectives.json` に 10 グループ・94 語（マイ単語 70・同梱語 24）の下書きを作った
- チェック（サーバーの `countHeadword` で見出し語の回数、例文の語数 3〜12、訳の文末、同梱語・作る語どうしの意味の重複、同梱語と同じ例文、同梱語の ID と綴り）:
  通らないのは「…」を含む 4 語（either … or …・neither … nor …・not only … but also …・both … and …）の「見出し語が例文に見つからない」だけ（想定どおり。次の検証タスクで扱う）
- `to` の品詞は「熟語（phrase）」にした（不定詞の to に合う品詞が無いため。同じグループの in order to・so that と誤答肢で並ぶ）
- ユーザーが確認し、この内容で進めることになった（2026-11-04）

### Phase 2: 取り込みスクリプト

- `server/src/admin/import-groups.ts` と Vitest（作る・2 回目は増えない・同梱語の ID 違いで何も書かない・`--dry-run`）
- ローカルの DB で `connectives.json` を取り込み、管理画面で 10 グループと中身を見る

#### Phase 2 の結果（2026-11-04）

- `server/src/admin/import-groups.ts`（`parseImportInput`・`importGroups`・`formatReports`）と CLI `server/src/import-groups.ts`
  （`node server/src/import-groups.ts [--dry-run] [file]`。file を省くと標準入力。DB は `VOCAB_DB_PATH`、無ければサーバーと同じ既定の場所）
  - 全体を 1 つのトランザクションで行う。`--dry-run` は最後まで流してから取り消すので、本番と同じ検証を通る
  - 2 回目は何も変えない（グループ・マイ単語の `updatedAt` も進めない）。同じ語を 2 つのグループに入れてもマイ単語は 1 つ
  - 失敗したら「取り込めなかった（何も書き込んでいない）: …」と出して終了コード 1
- Vitest 13 件（作る・2 回目は変えない・既存のグループに足す・同じ綴りのマイ単語の置き換え・dry-run・
  単語帳に無い ID／綴り違い／品詞の誤りで何も書かない・同じ名前のグループが複数・入力の形・`connectives.json` がそのまま入る）。
  全体 233 件成功・型チェック OK
- ローカルの使い捨て DB で CLI: dry-run → 取り込み（グループ 10・語 94・マイ単語 70）→ 2 回目は 0 件 → 壊れた入力は終了コード 1。
  その DB でサーバーを起動し、管理画面に 10 グループと中身（並び・意味・品詞）が出ること、`POST /api/sync` でグループが返ることを確認

### Phase 3: 本番に取り込む

- コミット・push（指示があったとき）→ g3plus で `git pull` → rebuild → `--dry-run` → 取り込み
- 管理画面で 10 グループを確認する
- iPhone で同期し、10 グループが出て、各語のカード（意味・例文）が表示できることを確認する

#### Phase 3 の結果（2026-11-04）

- `79ccd6e` を push → g3plus で pull・再ビルド（healthy。前回のデプロイ以降の server の変更もこのとき一緒に出た）
- 取り込む前に DB をバックアップ: `/home/ubuntu/vocab-blossom/server/data/backup-20261104-before-connectives.db`（グループ 2・マイ単語 21）
- dry-run（作る 10・足す 94・マイ単語を作る 70・置き換え 0）→ 取り込み（同じ結果）→ もう一度 dry-run で 0 件
- コンテナ内から `POST /api/sync`: グループ 12（既存 2 + 10）、マイ単語 91（21 + 70）
- 残り: iPhone で同期して、10 グループとカードが出ることの確認

## 影響範囲

- 追加: `data/groups/connectives.json`、`server/src/admin/import-groups.ts`（＋テスト）
- アプリ（iOS）のコードは変えない。サーバーの既存の処理（`AdminService`）も変えない
- 本番 DB にグループ 10 個とマイ単語 70 語が増える。取り消すときは管理画面でグループとマイ単語を消す

## テスト方針

- Vitest: 取り込みスクリプトの動き（上の Phase 2）
- データ: 例文の語数・見出し語・意味の重複をスクリプトで確認し、内容はユーザーが目で確認する
- 実機: 同期して 10 グループが出ること、カードが表示できること。4 択・穴埋めで正解が複数になる問題は、次の検証タスクで見る

## 決めること

1. ※の 5 語（when・since・once・yet・still）は、つなぎの意味のマイ単語を作るか、単語帳の語のまま入れるか（案: マイ単語を作る）
2. `to`（不定詞の「〜するために」）・`and`・`or` などのとても短い語も入れるか。
   穴埋めの文章は「見出し語がちょうど 1 回」で検証しているので、文章の中にほかの and・to が出ると通らない。
   入れておいて、次の検証タスクで扱いを決める案
