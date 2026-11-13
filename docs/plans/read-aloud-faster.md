# 英語の例文の読み上げを速くする

## 決めたこと（2026-11-12、試聴のあと）

- 例文のスタイルは **faster-b**（`natural conversational pace, not slow`）にする
- 再生の倍率は固定にせず、**設定画面で「読み上げの速さ」を選べるようにする**
  - ゆっくり 0.85 / ふつう 1.0（既定）/ 少し速い 1.15 / 速い 1.3 / とても速い 1.5
  - 例文だけでなく、読み上げ全部（見出し語・意味・例文・和訳、グループの読み上げも）に効く
  - 音声は作り直さず、鳴らすときに速める（`AVAudioPlayer` の `rate`。音程は変わらない）
  - 端末ごとの設定（`UserDefaults` の `settings.readAloudSpeed`）。同期・バックアップには入れない

## 目的・背景

英語の例文の読み上げが遅すぎる。穴埋め問題の回答後に気になった。ドリルも同じかもしれない。

穴埋め・ドリル・単語カードの読み上げは、どれも同じ道を通る
（`SessionView` / `WordCardView` → `GeminiReadAloudSpeaker.quiz` → サーバーの `POST /api/speech`、種類は `example`）。
だからドリルも同じ速さで、1 か所直せば全部に効く。

英語の例文の速さを決めているのは次の 3 か所。

| # | 場所 | 今の値 |
|---|------|--------|
| 1 | Gemini の声のスタイル（`server/src/ai/speech.ts` の `VOICES` の `example`） | Chobi: `warm and friendly, like a teacher reading to a beginner, calm natural pace` / Naruko: `bright and cheerful, like a classmate reading to a friend, calm natural pace` |
| 2 | 再生の速さ（`GeminiReadAloudSpeaker.swift` の `SystemReadAloudAudioPlayer`） | 等速（`AVAudioPlayer` の `rate` は使っていない） |
| 3 | 内蔵の声の例文の速さ（`ReadAloudSpeechEngine.swift` の `sentenceRate`） | 0.45（OS の既定は 0.5）。Gemini の声が取れないときだけ使う |

「初学者に読んで聞かせる」「落ち着いた速さ」というスタイルが、遅さのいちばんの元と見ている。

## 対応方針

**例文のスタイルを速い読み方に書き換える（#1）のを主にし、足りなければ再生の倍率（#2）で足す。**

- #1 は声そのものが自然に速くなるので、音がいちばんきれい。サーバーだけの変更で、アプリの更新は要らない。
  スタイルが変わると `speechVersion` が変わるので、端末に残っている例文の音声は自動で作り直される
  （最初の 1 回だけ、Gemini の生成待ちと料金がかかる）。
- Gemini のスタイルは「どのくらい速く」を数字で決められない。試聴して足りなければ、
  #2 で `AVAudioPlayer` の `enableRate` と `rate`（1.1〜1.2 倍など）を例文にだけかける。
  数字で決まり、音程は変わらず、音声の作り直しも要らない。
- #3 の内蔵の声は、Gemini の声と差が出ないように少し上げる。

### 変えないもの

- 見出し語（`word`）と日本語（`japanese`）のスタイル
- 文の間・語の間（`lineGap` / `itemGap`）

### グループの読み上げにも効く

グループの読み上げ（全 N 語）も同じ `example` のスタイルと同じ音声を使うので、**そちらの例文も速くなる**。
学習中だけ速くしたいなら、#1 ではなく #2 を `GeminiReadAloudSpeaker.quiz` にだけかける形になる。
今は「例文はどこでも同じ速さ」で進める。

## Step

### Step 1: 今の速さを測り、新しいスタイルを試聴して決める

- 代表の例文（短い文・長い文・穴埋めの出題文）を今のスタイルで 2 人ぶん作り、1 文の秒数を測る
- スタイルの候補で同じ文を作り、秒数と聞こえ方を比べる
  - 例: `calm natural pace` → `natural conversational pace` / `at a natural speaking speed, not slow`
  - 例: `reading to a beginner` を外す（「初学者に」がゆっくりを呼んでいる可能性がある）
- スタイルだけで足りるか、再生の倍率（#2）も要るかを決める
- **ユーザーに試聴してもらい、値を決める**
- 実装メモ（2026-11-12）: 試聴スクリプト `scripts/tts-audition.mjs` に例文の候補 `faster-a` / `faster-b` / `faster-c` と、
  読む種類を絞る `--kinds` を足した。Gemini のキーがこの PC に無く（`.env.local` が無い）、音声はまだ作れていない。
  キーを置いたら次で作る（2 人 × 4 スタイル × 4 文 = 32 本）:

  ```
  node --env-file=.env.local scripts/tts-audition.mjs --models gemini-3.8-flash-tts \
    --kinds example --styles readaloud,faster-a,faster-b,faster-c --words a1-0480,a2-1045,a1-0400,ph-0125
  ```

- 測った結果（2026-11-12、`gemini-3.8-flash-tts`、例文 4 つの合計。各 1 回ずつ作っただけなので、作り直すと少し変わる）

  | 読む人・候補 | 声が出ている秒 | 語/秒 | 今と比べた速さ |
  |--------------|---------------:|------:|---------------:|
  | Chobi 今 | 9.16 | 2.84 | 1.00 |
  | Chobi faster-a | 8.39 | 3.10 | 1.09 |
  | Chobi faster-b | 6.44 | 4.04 | 1.42 |
  | Chobi faster-c | 6.20 | 4.19 | 1.48 |
  | Naruko 今 | 7.13 | 3.65 | 1.00 |
  | Naruko faster-a | 7.33 | 3.55 | 0.97 |
  | Naruko faster-b | 6.66 | 3.90 | 1.07 |
  | Naruko faster-c | 6.42 | 4.05 | 1.11 |

  - 遅いのは主に Chobi（今は Naruko より 2 割ほど遅い）。「初学者に読む先生」が効いている
  - faster-a（「落ち着いた」を外すだけ）はほとんど変わらない
  - faster-b / faster-c で 2 人とも 4 語/秒 前後にそろう。Naruko はスタイルでは 1 割しか速くならない
  - 聞き比べのページ（再生の倍率も試せる）: https://claude.ai/artifact/KFxShmkC7cAt6Bj6pDH6xL
    （同じものが `tts-audition.local/index.html`。git 管理外）
  - 試聴の結果、faster-b に決定（上の「決めたこと」）

  | 候補 | Chobi | Naruko |
  |------|-------|--------|
  | 今（readaloud） | warm and friendly, like a teacher reading to a beginner, calm natural pace | bright and cheerful, like a classmate reading to a friend, calm natural pace |
  | faster-a | warm and friendly, like a teacher reading aloud, natural pace | bright and cheerful, like a classmate reading aloud, natural pace |
  | faster-b | warm and friendly, natural conversational pace, not slow | bright and cheerful, natural conversational pace, not slow |
  | faster-c | warm and friendly, at a brisk conversational pace | bright and cheerful, at a brisk conversational pace |

### Step 2: サーバーのスタイルを変える

- `server/src/ai/speech.ts` の `VOICES` の `example` を決めた値にする
- テスト（`speech.test.ts`）を直す。`example` の `speechVersion` だけが変わることを確かめる
- 本番に出す
- 実装メモ（2026-11-12）: `VOICES` の `example` を 2 人とも faster-b にした。サーバーのテスト 261 件は通過。
  スタイルの文面を固定で確かめるテストは足していない（既存のテストは `VOICES` の値をそのまま使う）。
- 本番に出した（2026-11-12、`2178dcf`）。コンテナは healthy、外からの `/health` は 200、Bearer なしの `/api/ping` は 401。
  本番の `/api/speech` で例文「I saw a rainbow on my way to school.」を作り、2 人とも 200・`audio/wav`・2.72 秒
  （前のスタイルの試聴では Chobi 3.44 秒・Naruko 2.80 秒）。
  開発機（この PC）に `.env` が無かったので `.env` は送らず、g3plus にあるものをそのまま使った

### Step 3: iOS に読み上げの速さの設定を入れる

- `ReadAloudSpeed`（`AppSettings.swift`）と `AppSettings.readAloudSpeed`
- 設定画面の「音声」に「読み上げの速さ」の選択
- `SystemReadAloudAudioPlayer` が鳴らすたびに設定を読み、`enableRate` と `rate` をかける（次の文から効く）
- 内蔵の声: 例文の `sentenceRate` を 0.45 → 0.5 に上げ、設定の速さをかける
  （内蔵の声の rate は倍率と比例しないので、だいたいの合わせ方）
- テスト: `AppSettingsTests` に保存と復元・既定・知らない値・内蔵の声の速さ
- 残してある音声を一度すべて消す（`ReadAloudVoiceStore.formatVersion` を 3 → 4）
  - スタイルの版が変わったことは、端末が次にその人・その種類の音声をサーバーへ頼むまで伝わらない。
    それまでは残してある古い（遅い）例文が鳴り、新しく作った例文だけ速い、という混ざった状態になる。
    全部残してあるグループでは頼む機会が無く、いつまでも古いままになる
  - 遅い音声に合わせて速さを「速い」にすると、新しい音声が速すぎることになるので、混ざらないように消す
  - **サーバーを先に本番へ出してから、アプリを入れる**（逆だと、消したあと古いスタイルで作り直してしまう）
  - 見出し語・日本語の音声も消えるので、最初の 1 回は全部作り直しになる（生成待ちと料金）
- 実装メモ（2026-11-12）: コードは書いた。**この PC（Linux）には Xcode が無いので、ビルドもテストもまだ通していない**

### Step 4: iPhone で確認（ユーザー）

- 穴埋めの回答後・ドリル・単語カード・グループの読み上げで、例文を聞く
- 設定の「読み上げの速さ」を変えて、次の文から速さが変わるか・音程が変わらないかを聞く
- 初回は例文の音声が作り直されるので、待ち時間が長くなりすぎないかも見る

## 影響範囲

- サーバー: `server/src/ai/speech.ts`（`example` のスタイル）、`speech.test.ts`
- iOS: `ReadAloudSpeechEngine.swift`、必要なら `GeminiReadAloudSpeaker.swift`、そのテスト
- 端末に残した音声: 例文のぶんだけ作り直しになる（自動）。古いファイルが残るなら消す処理があるか Step 2 で確かめる
- グループの読み上げの例文も速くなる

## テスト方針

- サーバー: `speech.test.ts` で `example` のスタイルと版が変わり、`word` / `japanese` の版は変わらないこと
- iOS: 内蔵の声の例文の速さ。再生の倍率を入れるなら、例文にだけ `AVAudioPlayer` に渡ること
- 最後は実機で聞いて決める（速さは耳で決めるしかない）

## 未決のこと

- 速さの選択肢の値（0.85〜1.5 の 5 段）がちょうどよいか。実機で聞いて直す
