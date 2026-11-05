# 読み上げの声を Gemini TTS にする

## 目的・背景

グループの読み上げ（[group-read-aloud.md](group-read-aloud.md)）は OS 内蔵の TTS（`AVSpeechSynthesizer`）で読んでいて、
声が機械的で聞き流しに向かない（2026-11-04）。esl-speaking-coach で使っている Gemini TTS の声と、
キャラ（Chobi / Naruko）の声の設定を持ってきて、読み上げの声を差し替える。

## 調べたこと（2026-11-04）

### esl-speaking-coach の作り（参考元）

- `EslSpeakingCoach/Voice/CloudPipeline/GeminiTTSClient.swift`
  - モデル `gemini-3.1-flash-tts-preview`。`POST .../models/{model}:streamGenerateContent?alt=sse&key=...`
  - ボディ: `contents[0].parts[0].text` = **スタイル前置文 + "\n" + 本文**、
    `generationConfig.responseModalities = ["AUDIO"]`、`speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName`
  - 返ってくる音声は `audio/l16` 24kHz mono の PCM16（リトルエンディアン）。SSE の `inlineData.data`（base64）をつなげる
  - 速さの数値指定は無い。**話速を決めているのは voice ではなくスタイル前置文**（実測。`docs/plans/archive/chobi-voice-speed.md`）
  - API キーはアプリの Keychain（`gemini-api-key`）に入れて、端末から直接呼んでいる
- キャラ（`EslSpeakingCoach/Conversation/ChatCharacter.swift`、`docs/specs/conversation-design.md`）

  | | Chobi | Naruko |
  | --- | --- | --- |
  | 役 | ホスト・先生役（落ち着いて温かい） | 仲間の生徒役（元気・好奇心） |
  | voice | `Leda`（Youthful） | `Aoede`（Breezy） |
  | スタイル前置文 | `Read aloud in a warm, lively, gently cheerful voice, like a friendly teacher chatting with a student. Speak at a brisk, natural conversational pace, without dragging out words:` | `Read aloud in a bright, energetic voice, full of curiosity, like an enthusiastic student chatting with friends:` |

  - 前置文の「brisk pace」は会話のテンポのため。初学者が単語を聞き取る読み上げでは、そのままだと速すぎる可能性がある

### Gemini TTS の今（公式ドキュメント 2026-11-04 時点）

- モデル
  - `gemini-3.8-flash-tts`（新・主力）、`gemini-3.8-flash-lite-tts`（新・速くて安い）
  - `gemini-3.1-flash-tts-preview` は **レガシー扱い**（3.8 への移行を推奨。API の形は同じ、3.8 Flash-Lite が後継とされる）。停止日はまだ出ていない
  - `gemini-2.5-flash-preview-tts` / `gemini-2.5-pro-preview-tts` も残っている
- 言語: 100 以上。**日本語に対応**。言語は自動判定（言語の指定は無い）
- 声: 既定の 30 種（Zephyr, Puck, Charon, Kore, Fenrir, Leda, Orus, Aoede, Callirrhoe, Autonoe, Enceladus, Iapetus, Umbriel,
  Algieba, Despina, Erinome, Algenib, Rasalgethi, Laomedeia, Achernar, Alnilam, Schedar, Gacrux, Pulcherrima, Achird,
  Zubenelgenubi, Vindemiatrix, Sadachbia, Sadaltager, Sulafat）＋拡張ライブラリ（`GET /v1beta/voices`）・自作の声
- 話し方の制御
  - 新しい Interactions API（`POST /v1beta/interactions`）では、本文とは別に `speech_metadata.style`（例 `"speaking slowly"`）で指定できる
  - 本文中のタグ（`<short pause>` `<laugh>` など）も使える。速さの数値指定は今も無い
  - 2 人まで 1 リクエストで話者を分けられる（今回は 1 文 1 声なので使わない）
- 出力: 24kHz mono 16bit PCM。`audio/wav`（ヘッダ付き）・`audio/l16`（ストリーミング）などを選べる
- 料金（1M トークンあたり。音声は 25 トークン/秒。無料枠あり）

  | モデル | 入力テキスト | 出力音声 | 10 秒あたり |
  | --- | --- | --- | --- |
  | `gemini-3.8-flash-tts` | $0.50 | $9.00 | 約 $0.0023 |
  | `gemini-3.8-flash-lite-tts` | $0.50 | $6.00 | 約 $0.0015 |
  | `gemini-3.1-flash-tts-preview` | $1.00 | $20.00 | 約 $0.005 |

  - 3.8 の料金は **2027-01-01 から倍**になる
  - 見積もり: 1 語（単語・意味・例文・和訳）で音声およそ 9 秒 → 3.8 Flash で約 $0.002 / 語、1,000 語で約 $2。
    一度作った音声を端末に残せば、ループで何周しても追加の料金はかからない

## 決めたこと（2026-11-04）

1. **声**: Chobi（Leda）と Naruko（Aoede）の **2 人分の音声を両方作り、再生するときにランダムに選ぶ**
   - 選ぶ単位は **1 語ごと**（1 語の「単語 → 意味 → 例文 → 和訳」は同じ人が読む）とした（こちらで決めた。文ごとに変えたいなら直す）
   - 料金は 1 人分の 2 倍（3.8 Flash で約 $0.0045 / 語、1,000 語で約 $4.5）。端末に残すので 1 語 1 回
2. **作る場所**: サーバー経由（`POST /api/speech`、`GEMINI_API_KEY` はサーバーの env）

## 対応方針

### 声の割り当て（キャラ）

- 上の「決めたこと」のとおり、2 人分を作って 1 語ごとにランダムに選ぶ
  - 前の語と同じ人が続きすぎないよう、ランダムでも 3 語以上は続けない、などは Phase 3 で決める
  - ある語で片方の音声しか取れていなければ、取れている方で読む
- スタイル前置文は esl-speaking-coach のものを土台に、読み上げ用に変える（Phase 1 の試聴で決める）
  - 単語: はっきり、少しゆっくり（初学者が新しい語を聞く想定）
  - 例文: 自然な速さだが、急がない（会話用の「brisk」は外す）
  - 日本語: 落ち着いて、はっきり
- 前置文が読み上げに混ざらないか（とくに 1 語だけの短い本文）を試聴で確かめる。混ざるなら Interactions API の `speech_metadata.style` に移す

### どこで音声を作るか

- **サーバー（g3plus）で作る**。`POST /api/speech`（共有シークレットで守る。`/api/passages` と同じ形）
  - Gemini の API キーは `GEMINI_API_KEY`（サーバーの env）。アプリには入れない（Claude の AI チェックと同じ考え方）
  - モデルは `GEMINI_TTS_MODEL`（既定は Phase 1 の試聴で決める。`gemini-3.8-flash-tts` か `-lite`）
  - 入力: 文・声（キャラ）・種類（単語 / 例文 / 日本語）。前置文はサーバー側に持つ（アプリの更新なしで調整できる）
  - 出力: WAV（24kHz mono 16bit）
- 端末に音声を残す（`Library/Caches/read-aloud/`）。キーは「モデル・声・前置文の版・文」のハッシュ
  - WAV は 1 語で約 430KB と大きいので、端末で AAC（m4a）に変換して残す（1 語で約 40KB 程度の見込み）

### 再生

- `ReadAloudSpeaking` の実装を足す（`GeminiReadAloudSpeaker`）。`ReadAloudPlayer`・画面はそのまま使う
  - 文ごとに音声ファイルを `AVAudioPlayer` で順に鳴らし、文の間・語の間の間（0.25 秒・0.8 秒）は今と同じ
  - 文を鳴らし始めたら `onLineStart`、全部鳴らし終えたら `onFinish`（今の約束どおり）
- 先読み: 今の語を読んでいる間に、次の数語の音声を 2 人分取っておく（プロトコルに「この先読む文」を渡す口を足す）
- 音声が取れないとき（オフライン・サーバーの失敗・キー未設定）は、その文だけ今の OS 内蔵 TTS（`ReadAloudSpeechEngine`）で読む。
  読み上げを止めない
- 音声セッション・割り込み・ロック画面の操作は今の仕組み（`LearningAudioSession`・`ReadAloudNowPlaying`）をそのまま使う

### 今回やらないこと

- 提示カード・リスニングクイズの 1 語の読み上げ（`SpeechService`）の Gemini 化（作った音声の置き場ができるので、後で検討）
- 音声の全語の事前生成（「グループの音声をまとめて作る」ボタンなど）。先読みで足りなければ足す

## Phase

### Phase 0: 決める

- 上の「決めたこと」のとおり（2026-11-04）。モデルは Phase 1 の試聴で決める

### Phase 1: 試聴して声と前置文を決める

- `scripts/` に Gemini TTS を直接呼ぶ試聴スクリプト（Node）。実際のグループの語（単語・意味・例文・和訳）で WAV を作る
- 比べる: モデル（3.8 Flash / 3.8 Flash-Lite）× 前置文の案。話速（words/sec）と、前置文が読み上げに混ざらないか、日本語の自然さ
- 決めた値をこのプランに残す。ローカルに `GEMINI_API_KEY` が要る
- 実装メモ（2026-11-04）: `scripts/tts-audition.mjs`。キーは新しく作ったものを `.env.local`（git 管理外）に置き、
  `node --env-file=.env.local scripts/tts-audition.mjs` で動かす。出力は `tts-audition.local/`（git 管理外）。
  既定は 3 語（about・sit down・adjust）× 3.8 Flash / Flash-Lite × Chobi / Naruko × 読み上げ用の前置文。
  `--styles readaloud,original` で esl-speaking-coach の前置文とも比べられる
- **決めた値（2026-11-04、実際のグループ unit2-part1 の 10 語 × Chobi / Naruko で試聴して問題なし）**
  - モデル: **`gemini-3.8-flash-tts`**（`GEMINI_TTS_MODEL` の既定）
  - API: **Interactions API**（`POST /v1beta/interactions`）。スタイルは本文に混ぜず `speech_metadata.style` で渡す
    （3.8 は本文の頭に前置文を書くとそのまま読まれるため）。出力は `audio/l16` 24kHz
  - 声: Chobi = `Leda`、Naruko = `Aoede`
  - スタイル（文の種類ごと。試聴スクリプトの `readaloud`）

    | 種類 | Chobi | Naruko |
    | --- | --- | --- |
    | 単語 | `warm and clear, like a friendly teacher, speaking slowly` | `bright and cheerful, clear, speaking slowly` |
    | 例文 | `warm and friendly, like a teacher reading to a beginner, calm natural pace` | `bright and cheerful, like a classmate reading to a friend, calm natural pace` |
    | 日本語（意味・和訳） | `warm and friendly, like a teacher explaining, calm natural pace` | `bright and cheerful, like a classmate explaining to a friend, calm natural pace` |

  - 実測: 1 文あたり 1.4〜5 秒、生成の待ち時間は 1 文 2〜3.4 秒。英語の例文は 1.9〜3.2 words/sec、単語は 1 語 0.8〜1.7 秒
    → 1 語（4 文）を順に作ると約 10 秒かかるので、iOS では 4 文を並べて頼み、先読みで待ち時間を隠す

### Phase 2: サーバー（`POST /api/speech`）

- `server/src/ai/gemini-tts.ts`（Gemini の呼び出し）・`server/src/ai/speech.ts`（入力の検証・前置文・声の割り当て）
- `config.ts` に `GEMINI_API_KEY`・`GEMINI_TTS_MODEL`。キー未設定なら 503 系で返し、アプリは内蔵 TTS に落とす
- `docs/specs/deploy-g3plus.md` に env を追記（g3plus の `.env` への追加は手で行う）
- 実装メモ（2026-11-04）
  - 入力 `{ text, speaker: "chobi" | "naruko", kind: "word" | "example" | "japanese" }`（意味と和訳は `japanese`）。
    出力は `audio/wav`（24kHz mono 16bit）と、ヘッダ `x-speech-version`（モデル・声・スタイルの短いハッシュ。
    iOS が端末に残す音声の鍵に使い、サーバーでスタイルを直したら作り直せる）
  - 失敗: 入力不正 400 / キー未設定 503（`tts-unavailable`）/ 上限 429 / Gemini の失敗 502（Gemini の 429 は 429 で返す）
  - 上限は AI チェック・文章とは別の枠で 10 分 600 回（1 語 = 2 人 × 4 文 = 8 回）
  - サーバーには音声を残さない（端末に残す）。実際のキーで `adjust` を読ませ、200・1.7 秒の WAV が返ることを確かめた
  - g3plus の `.env` に `GEMINI_API_KEY` を足してデプロイした（2026-11-04）。本番で Bearer なし 401、Bearer ありで 200・`audio/wav`（24kHz mono 16bit）を確認

### Phase 3: iOS（声の差し替え）

- `SpeechClient`（`POST /api/speech`）、音声の置き場（ハッシュ → m4a）、`GeminiReadAloudSpeaker`、先読み、内蔵 TTS への切り替え
- 読み上げ画面は変えない。DebugSeed `group-read-aloud` は偽のクライアントで動くようにする
- 実装メモ（2026-11-04）
  - `Core/Sync/SpeechClient.swift`（`SpeechAPI`・`SpeechFetching`・`SpeechClient`）。タイムアウト 20 秒。エラーは AI チェックと同じ `WordAssistError`
  - `Core/ReadAloudVoiceStore.swift`: `Library/Caches/read-aloud/` に 1 文 1 ファイル。鍵は「版・人・種類・文」の SHA-256。
    人・種類ごとに最後に見た版を `versions.json` に覚え、版が変わったら古い音声は使わない。WAV → m4a（AAC）に変換して残す（失敗したら WAV のまま）
  - `Core/GeminiReadAloudSpeaker.swift`: `ReadAloudSpeaking` の実装（`.shared`）。読み上げ画面の既定の声をこれにした
    - 1 語の 4 文をまとめて頼み、届いた順ではなく文の順に `AVAudioPlayer` で鳴らす。文の間 0.25 秒・語の間 0.8 秒
    - 読む人は 1 語ごとにランダム。2 語続けて同じなら次はもう 1 人。片方の人の音声だけそろっていれば、そろっている方
    - 取れなかった文はその文だけ内蔵の声（`ReadAloudSpeechEngine`）。失敗したら 30 秒（キー未設定・認証・上限は 5 分）サーバーへ頼まない
    - 割り込み（通話・イヤホンが抜けた）は内蔵の声の側の見張りを使い回す
    - `fetcher` は起動時にサーバーの設定から入れる（`VocabBlossomApp`）。設定が無ければすべて内蔵の声
  - 先読み: `ReadAloudSpeaking.prepare(_:)` を足した（既定は何もしない）。`ReadAloudPlayer` は読み始めるたびに「今の語 + 次の 3 語」
    （ループなら頭に戻って数える）を渡し、Gemini の声は 2 人分を同時 2 本まで取りに行く
  - DebugSeed `group-read-aloud` は偽のサーバー（`DebugSpeechFetcher`。0.8 秒待って、文の長さだけ Chobi は低い音・Naruko は高い音）
  - テスト: Swift Testing 18 件（順に鳴らす・残した音声を使う・文ごとの切り替え・失敗後の休み・停止・人の選び方・先読み・置き場・通信）。
    全 256 件が通り、SwiftLint 警告 0。シミュレータで DebugSeed を起動し、文の強調と語ごとの人の切り替えを確かめた

### Phase 4: 実機確認

- 2026-11-04: **iPhone のスピーカーで音が割れ気味**。調べた結果:
  - Gemini の音声はピーク -0.7〜-1.7 dBFS・RMS -13〜-18 dBFS とほぼ上限いっぱい（内蔵の日本語の声は RMS -25 dBFS で、約 9 dB 大きい）
  - 端末で AAC（約 34 kbps）にして 96kHz で見ると、81 本中 4 本の真のピークが 0 dBFS を超える（最大 +0.74 dBFS）
  - 対応: 残すときに大きさをそろえる（RMS -20 dBFS、ピークは -4 dBFS まで、上げるのは +6 dB まで）、AAC を 64 kbps に。
    同じ処理を手元で試すと真のピークは最大 -2.46 dBFS、RMS は -20〜-22.7 dBFS にそろった。
    置き場に残し方の版（`format`）を足し、版が変わったら残してある音声を消して作り直す（今回 2）
  - 1 文 3.3 秒で約 33KB（64 kbps）。1 語・1 人で約 80KB

- 声・速さ・日本語の自然さ、最初の語が鳴るまでの待ち時間、ロック中・ループ中の先読み、オフラインで内蔵 TTS に落ちること
- 読み上げ本体の Phase 4（実機確認）と一緒に行ってよい

## 影響範囲

- サーバー: `server/src/app.ts`（ルート）、`server/src/config.ts`、`server/src/ai/`（新規 2 ファイル）、`docs/specs/deploy-g3plus.md`
- iOS: `Core/`（`SpeechClient`・音声の置き場・`GeminiReadAloudSpeaker`）、`Core/ReadAloudPlayer.swift`（先読みの口）、
  `Features/Groups/ReadAloudView.swift`（使う声の実装を差し替える場所だけ）、`App/DebugSeed.swift`
- 同期・データ（WordEntry・進捗）は変えない
- 料金: Gemini TTS（上の見積もり。端末に残すので 1 語 1 回）

## テスト方針

- サーバー（vitest）: 入力の検証（空文・長すぎる文・知らない声）、Gemini を偽物にして WAV を返す・失敗を返す、キー未設定、認証
- iOS（Swift Testing）: 置き場のキー（同じ文・声なら同じ、前置文の版が変われば別）、`GeminiReadAloudSpeaker` が順に鳴らして
  `onLineStart` / `onFinish` を呼ぶ、音声が取れない文は内蔵 TTS に回す、`stop` 後に前の知らせを呼ばない（偽の再生・偽のクライアントで）
- 既存テストがすべて通る・SwiftLint 警告 0
- 声の良し悪しは Phase 1 の試聴と Phase 4 の実機で耳で確かめる
