# AI のモデルを iOS の設定画面で選べるようにする

## 目的・背景

AI のモデルは今、サーバーの env（`ANTHROPIC_MODEL` / `GEMINI_TTS_MODEL`）でしか変えられない（2026-11-04 時点で本番は未設定 = 既定）。
iOS アプリの設定画面から選べるようにする。

| 使い道 | API | 今のモデル |
| --- | --- | --- |
| 自作語の AI チェック | `POST /api/word-assist` | `claude-opus-5-5` |
| 穴埋めの文章（問題作成） | `POST /api/passages` | `claude-opus-5-5` |
| 読み上げの声（TTS） | `POST /api/speech` | `gemini-3.8-flash-tts` |

## 調べたこと（2026-11-04）

### Claude

- 選べるのは **Opus 5.5（`claude-opus-5-5`）・Sonnet 5.5（`claude-sonnet-5-5`）**（ユーザーの指定）
- Sonnet 5.5 でも今の呼び方（`fallbacks: "default"` + `server-side-fallback-2026-07-01`、`output_config.effort: "low"`・JSON スキーマ、
  `cache_control`）がそのまま使える（claude-api のリファレンスで確認）。料金は Opus 5.5 の半分（入力 $2 / 出力 $10 per MTok）
- プロンプトのキャッシュはモデルごとなので、切り替えた直後の 1 回はキャッシュが効かない

### Gemini TTS

`GET /v1beta/models` で TTS のモデルは 5 つ。サーバーの呼び方（Interactions API・`speech_metadata.style`・`audio/l16`・Leda / Aoede）で実際に読ませた:

| モデル | 結果 | 待ち時間（1 文） |
| --- | --- | --- |
| `gemini-3.8-flash-tts` | OK | 3.0〜3.4 秒 |
| `gemini-3.8-flash-lite-tts` | OK | 2.5〜2.7 秒 |
| `gemini-3.1-flash-tts-preview` | 400（`audio/l16` に未対応）。レガシー扱い | - |
| `gemini-2.5-flash-preview-tts` | 400（`speech_metadata` に未対応） | - |
| `gemini-2.5-pro-preview-tts` | 400（`speech_metadata` に未対応） | - |

- 3.1 / 2.5 は本文の頭にスタイルを書く別の呼び方が要り、3.8 より高い（3.1 は出力 $20 / MTok）。**選べるのは 3.8 Flash と 3.8 Flash-Lite の 2 つ**にする
- `gemini-2.5-flash-native-audio-*` はリアルタイム会話（Live API）用で TTS ではない

## 対応方針

- **設定は端末ごと**（`AppSettings`・UserDefaults）。iOS はリクエストに `model` を付けて送り、サーバーは許可リストで確かめて使う
  - 許可リストに無いモデルは 400。`model` が無ければ今までどおり env（無ければコードの既定）
  - 古いアプリ（`model` を送らない）も今までどおり動く。新しいアプリ + 古いサーバーでは `model` は無視される（既定で動く）
- 管理画面の AI チェック（`/admin/word-assist`）は env のまま
- 既定は今と同じ（Opus 5.5・3.8 Flash）
- **読み上げの音声の置き場**: 鍵に TTS のモデルを入れ、「版」もモデルごとに覚える（切り替えて戻しても、前のモデルの音声を使える）
- 穴埋めの文章はサーバーで語ごとにためているので、モデルを変えても作り直さない（新しい語から新しいモデルで作る）

### 設定画面

- 「AI」セクション（サーバーの設定があるときだけ出す）
  - 「問題作成・AI チェック」: Opus 5.5（高品質）/ Sonnet 5.5（速い・安い）
  - 「読み上げの声」: Gemini 3.8 Flash（標準）/ Gemini 3.8 Flash-Lite（速い・安い）

## Phase

### Phase 1: サーバー（`model` を受け付ける）

- `server/src/ai/models.ts`: 許可リスト（`CLAUDE_MODELS`・`TTS_MODELS`）と `parseModel`
- word-assist / passages / speech の入力に `model`（任意）。`WordAssistant.suggest`・`PassageWriter.write`・`SpeechSynthesizer.synthesize` にモデルを渡す
- `x-speech-version` は実際に使ったモデルで作る
- テスト（vitest）: 許可リスト外は 400、`model` 無しは既定、渡したモデルが AI の呼び出しに届く
- 実装メモ（2026-11-04）: 上のとおり。vitest 7 件を足して全 220 件が通り、型チェックもエラーなし

### Phase 2: iOS（設定画面・送る）

- `AppSettings` に `claudeModel`・`ttsModel`（enum。rawValue がモデル ID）
- `WordAssistClient`・`PassageClient`・`SpeechClient` がリクエストに `model` を付ける（設定は送るときに読む）
- `GeminiReadAloudSpeaker`・`ReadAloudVoiceStore`: リクエスト（= 置き場の鍵）にモデル、版はモデルごと
- 設定画面に「AI」セクション
- テスト（Swift Testing）: 送る本文に `model`、置き場の鍵・版がモデルで分かれる、設定の保存
- 実装メモ（2026-11-04）
  - `Core/AIModels.swift`: `ClaudeModel`・`TTSModel`（rawValue がモデル ID）と `AIModelPreference`（UserDefaults から読む。知らない値は既定）
  - `AppSettings.claudeModel`・`ttsModel`（キー `settings.claudeModel`・`settings.ttsModel`）
  - `WordAssistClient`・`PassageClient` は送るたびに `AIModelPreference` を読んで `model` を付ける（テストでは差し替え）
  - `SpeechAPI.Request` に `model`（= 置き場の鍵）。`GeminiReadAloudSpeaker` は語を読み始めるとき・先読みのときに設定を読む。
    置き場の版は「モデル/人/種類」ごと。残し方の版を 3 に上げた（入れ直すと前の音声は消えて作り直す）
  - 設定画面に「AI」セクション（サーバーの設定があるときだけ）。シミュレータのデモ起動ではサーバーの設定が無いので、画面は実機で見る
  - Swift Testing 3 件を足して全 262 件が通り、SwiftLint 警告 0

### Phase 3: デプロイ・実機確認

- サーバーをデプロイ（env は変えない）。本番で `model` 付きの `/api/speech`・`/api/word-assist` が通ること、許可リスト外が 400 になること
- 実機で切り替えて、AI チェック・穴埋め・読み上げが動くこと

## 影響範囲

- サーバー: `server/src/ai/`（models.ts 新規、word-assist / claude / passages / claude-passages / speech / gemini-tts）、テスト
- iOS: `Core/AppSettings.swift`、`Core/Sync/`（3 つのクライアント）、`Core/GeminiReadAloudSpeaker.swift`、`Core/ReadAloudVoiceStore.swift`、
  `Features/Settings/SettingsView.swift`、テスト
- 同期・データ（WordEntry・進捗）は変えない

## テスト方針

- サーバー: vitest（上の Phase 1）。既存テストがすべて通る
- iOS: Swift Testing（上の Phase 2）。既存テストがすべて通る・SwiftLint 警告 0
- 本番: model 付きのリクエストを curl で確かめる（Phase 3）
