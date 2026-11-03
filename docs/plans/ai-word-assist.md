# 自作語の登録に AI チェック（タイポ・活用形・意味の下書き）を入れる

作成日: 2026-11-02

## 目的・背景

- 単語帳（同梱語 2,443 件）に無い語を自作語として登録するとき、**打ち間違い（beautifull）や活用形（went / children）
  のまま登録してしまう**と、同梱語と重複した・綴りの誤った自作語が増える
- 自作語を作るときは意味・品詞・例文を手で入れる必要があり、初学者には負担が大きい
- そこで **AI（Claude API）に入力を見てもらい**、
  1. 綴りの誤り・活用形・英米の綴りの違い・日本語での入力を **同梱語に寄せる**（同梱語があればそれを選ばせる）
  2. 同梱語に本当に無い語だけ、**意味・品詞・例文・例文訳を AI が下書き**して自作語にする
- API キーはアプリに入れられないので、管理画面サーバー（`vocab.chobi.me`）に API を 1 本足して呼ぶ
  （前提: [admin-server](archive/admin-server.md)。env `ANTHROPIC_API_KEY` は未設定なら AI 機能だけ使えない）

## 対応方針

### サーバー: `POST /api/word-assist`（iOS 用・Bearer）と `POST /admin/word-assist`（管理画面用）

- リクエスト `{ "text": "beautifull" }`（前後の空白を落として 1〜60 文字。英語でも日本語でもよい）
- AI には **同梱語の見出し語の一覧をシステムプロンプトに入れる**（約 18,000 文字。プロンプトキャッシュで 2 回目以降は安い）。
  入力が同梱語の打ち間違い・活用形・綴りの違い・熟語の言い回しの違い・日本語訳なら、その同梱語を候補の先頭に出すよう指示する。
  意味が近いだけの別の語（gigantic → big）には寄せない（覚えたい語を勝手に変えない）
- 出力は構造化出力（JSON Schema）で候補 1〜3 件。各候補は
  `word`（見出し語の形）/ `pos` / `meaning`（初学者向けの短い日本語）/ `example` / `exampleJa` /
  `reason`（`exact` そのまま正しい・`typo` 綴りの誤り・`inflection` 活用形・`variant` 綴りや言い回しの違い・`translation` 日本語から）
- **同梱語との照合はサーバーで行う**（AI の返した `word` を綴りで `BundledWords.findBySpelling`）。
  AI が一覧に無い語を「ある」と言っても、照合できなければ自作語扱い。照合できた候補には同梱語の `id`・意味などを付けて返す
- 応答 `{ text, candidates: [{ word, pos, meaning, example, exampleJa, reason, bundled: { id, word, meaning, pos, level } | null }] }`
- エラー: キー未設定 503 `ai-unavailable` / 入力不正 400 / 回数制限 429 / AI の失敗 502
- 回数制限: サーバー全体で 10 分に 60 回まで（メモリ内。iOS に入れた共有シークレットが漏れても請求が膨らまないように）
- モデル: `claude-opus-5-5`・effort `low`・`fallbacks: "default"`（拒否時に別モデルで再実行）。
  env `ANTHROPIC_MODEL` で差し替えられる（安くしたいときは `claude-haiku-5-5` など）
- 依存に公式 SDK `@anthropic-ai/sdk` を足す。テストでは AI の部分を差し替える（実際の API は呼ばない）

### iOS: 自作語エディタに「AI で調べる」

- `ServerConfig.plist` があるとき（同期と同じ条件）だけ表示。無ければ今までどおり
- 「単語帳から追加」で見つからないときの「「○○」を自分で作って追加する」から開いたエディタは、**開いた時点で自動で AI に聞く**。
  グループ詳細などから開いたエディタは、英語（または意味）を入れて「AI で調べる」を押す
- 結果の出し方
  - **同梱語に当たった候補**: 「単語帳の「take」（取る）を選ぶ」ボタン（今の重複案内と同じ動き。選んだら自作しない）
  - **同梱語に無い候補**: 「beautiful（形容詞）美しい」と理由（「綴りの誤りかもしれません」など）、「この内容を入れる」で
    英語・意味・品詞・例文・例文訳をまとめて入れる
  - 先頭の候補が `exact` で同梱語に無ければ、**空いている欄だけ**自動で埋める（入力済みの欄は上書きしない）
  - 失敗したら理由を 1 行出し、手入力はそのまま続けられる
- 通信は `SyncClient` と同じ作り（`URLSession` 差し替えでテストできる `WordAssistClient`）

### 管理画面: 自作語のフォームに「AI で調べる」

- グループ詳細の「自作語を作る」とマイ単語の作成フォームに「AI で調べる」ボタンを置き、素の JS で `/admin/word-assist` を呼ぶ
- 同梱語に当たった候補は「グループに追加」（グループ詳細のときだけ。既存の `POST /admin/groups/:id/words`）、
  無い候補は「入力する」でフォームに入れる

## Phase

- Phase 1: サーバーの `POST /api/word-assist`（AI 呼び出し・同梱語との照合・回数制限・テスト）
- Phase 2: iOS の自作語エディタに AI チェック
- Phase 3: 管理画面のフォームに AI チェック
- Phase 4: g3plus へ反映（`ANTHROPIC_API_KEY` を `.env` に入れてもらい、再ビルド）

## 影響範囲

- server: `src/ai/`（新規）、`src/app.ts`（ルート）、`src/config.ts`（`ANTHROPIC_MODEL`）、`src/admin/pages.ts`、`package.json`
- iOS: `Core/Sync/`（クライアント・モデル）、`Features/Groups/CustomWordEditorView.swift`、`WordPickerView.swift`、`VocabBlossomApp.swift`（環境に渡す）
- docs: `docs/specs/deploy-g3plus.md`（env の追記）

## テスト方針

- サーバー（Vitest。AI は偽物に差し替え）
  - 入力の検証（空・長すぎ → 400）、キー未設定 → 503、Bearer なし → 401
  - AI の候補を同梱語と照合して `bundled` が付く / 一覧に無い語は `null` / 同じ綴りの候補は 1 つにまとめる
  - AI が失敗 → 502、回数制限を超える → 429
  - システムプロンプトに同梱語の一覧が入り、毎回同じ文字列になる（キャッシュが効く）
  - `/admin/word-assist` は `ADMIN_ENABLED` が無ければ 404、Origin が違えば 403
- iOS（Swift Testing）: `WordAssistClient` の要求・応答の読み取り・エラー（401 / 429 / 503 / オフライン）、
  候補の下書きへの反映（空欄だけ埋める）
- 実機相当の確認: ローカルサーバーを実キーで起動し、beautifull / went / 世話をする / serendipity で候補を確認。シミュレータで画面を確認
