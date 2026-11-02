# vocab-blossom 用の管理画面（Web）とサーバー

作成日: 2026-11-02

## 目的・背景

- グループ（マイ単語帳）とその中の単語・フレーズは、今は iPhone の中でしか作れない。
  **PC のブラウザからグループと中身を管理**し、アプリに反映したい
- 自作語を登録するときに **Claude API でタイポチェック**したいが、API キーをアプリに埋め込むと抜き出される。
  キーを持つサーバーが必要（キーは管理画面サーバーの起動時の環境変数 `ANTHROPIC_API_KEY` に入れる）

このプランでは管理画面とサーバーを作り、g3plus に配置し、アプリと同期する。
AI タイポチェック（TODO の別タスク）はこのサーバーに API を 1 本足す形で、管理画面の完成後に行う。

## 決定事項（ユーザー確認済み）

- **管理画面でできること**
  - グループ: 追加・名前の変更・削除
  - グループ内の単語・フレーズ: 追加・外す・編集
    （同梱語を検索して追加する / 自作語をその場で作る。自作語は編集・削除できる）
  - **同梱語（アプリに最初から入っている語）の英語・意味などは編集しない**。グループに入れる・外すだけ。
    同梱語を直すときは今までどおり `data/decks/*.json` を直してアプリをビルドし直す
- **技術**: Node 24 + TypeScript、**Web フレームワークは使わない**（`node:http` 直書き）
- **ホスト名**: `vocab.chobi.me`（g3plus-ops 経由で配置）
- **リポジトリ**: public → g3plus 上に `git clone` して build context にする

## 構成

### 置き場所・技術

- このリポジトリの `server/` に置く。同梱の単語 JSON（`data/decks/`）をそのまま読んで、同梱語の検索・表示に使う
- 依存は SQLite の **better-sqlite3** だけ（g3plus の各サービスと同じ）。Claude API の呼び出しは
  タイポチェックのタスクで公式 SDK（`@anthropic-ai/sdk`）を足す
- TypeScript は **Node 24 の型除去でそのまま起動**する（`node server/src/main.ts`。ビルド工程・tsx 不要）。
  `tsconfig` で `erasableSyntaxOnly` と `allowImportingTsExtensions` を有効にし、enum など型除去で消せない書き方を禁止する
- 中身は **Web 標準の `Request` → `Response` を返す関数（`handle`）** として書き、`node:http` との変換は薄いアダプタ 1 つにまとめる。
  テストはサーバーを起動せずに `handle(new Request(...))` で書ける
- 自分で用意する小さな部品（フレームワークの代わり）
  - **ルーティング**: メソッド + パスのパターン（`/admin/groups/:id` など）の表と照合関数
  - **認証**: Bearer の照合（`crypto.timingSafeEqual`）と `ADMIN_ENABLED` のチェック
  - **フォーム**: `request.formData()`（Node 24 の標準）で受け取る。JSON API は `request.json()`
  - **HTML**: タグ付きテンプレート（`html\`...\``）で、埋め込む値を必ずエスケープする関数を用意する（XSS 対策）。
    レイアウト（共通のヘッダー・CSS）はただの関数にする。画面の動きは最小限の素の JS
  - **CSRF**: 管理画面の POST は Cloudflare Access の後ろだが、`Origin` ヘッダが自分のホストと一致するかを確かめる
  - **エラー処理・ログ**: 例外は 500 にしてログに出す。リクエストごとに 1 行のアクセスログ
- テストは既存の Vitest（`src/` のデータ検証と同じ設定に `server/` を足す）

### 配置（g3plus。デプロイ共通規約は `~/Projects/g3plus-ops/CLAUDE.md`）

- アプリコード: g3plus 上の `/home/ubuntu/vocab-blossom/` に clone（public リポジトリの方式）。更新は `git pull` → rebuild
- デプロイ設定の正本は `g3plus-ops/vocab-blossom/`（`docker-compose.yml` / `Dockerfile` / `.env` / `.env.example`）
- デプロイ契約（Node・起動コマンド・必須 env・永続化先）の正本はこのリポジトリの `docs/specs/deploy-g3plus.md`
- ポートは **3014**（g3plus の次の空き）。**ホスト非公開**で、`n8n_default` ネットワークの cloudflared からだけ届く
- コンテナ内はリポジトリと同じ並び（`/app/server/` と `/app/data/decks/`）にする。起動は `node server/src/main.ts`
- SQLite は volume で永続化（`/home/ubuntu/vocab-blossom/server/data:/app/server/data`）。
  `/app/data` は同梱の単語 JSON の置き場所なので volume にしない（Phase 1 で変更）

### 認証（trip-note と同じ方式）

| パス | 認証 | Cloudflare Access |
| --- | --- | --- |
| `/api/*`（iOS 用） | `Authorization: Bearer <API_SHARED_SECRET>` | Bypass（Everyone） |
| `/admin/*`（管理画面） | Access だけ。さらに `ADMIN_ENABLED=on` のときだけ有効（未設定は 404 = fail-safe） | Allow（Google / Emails） |
| `/health` | なし | Bypass |

- iOS は `ios/VocabBlossom/Resources/ServerConfig.plist`（**git 管理外**。`BASE_URL` と `API_KEY`）をビルドに同梱する。
  **リポジトリが public なので、secret は絶対にコミットしない**（`.gitignore` に入れ、`ServerConfig.example.plist` だけ置く）。
  ファイルが無ければサーバー機能を使わず、今までどおりオフラインで動く
- env: `API_SHARED_SECRET`（必須、`openssl rand -hex 32`）/ `ANTHROPIC_API_KEY`（任意。未設定なら AI 機能だけ使えない）/
  `ADMIN_ENABLED` / `VOCAB_DB_PATH=/app/server/data/vocab-blossom.db` / `PORT=3014`

### 同期するデータ

- **同期する**: グループ（`id` / 名前 / 単語 ID の並び / 日時）と自作語（`wordId` / 英語 / 意味 / 品詞 / 例文 / 例文訳 / 日時）
- **同期しない**: 学習の進捗（`WordProgress`）・回答ログ（`AnswerLog`）・設定。今までどおり端末の中だけ
- 同梱語そのものはアプリにもサーバーにも同じ JSON があるので、グループには ID だけ入れればよい

### 同期のしくみ

- サーバーが「ハブ」になり、端末と管理画面の変更を集める。今は自分の端末 1 台の想定（複数台でも壊れない作りにはする）
- サーバーはレコードを更新するたびに通し番号（`rev`）を振る。端末は「前回どこまで受け取ったか」（`cursor`）を覚えておく
- `POST /api/sync`
  - 送る: `cursor` と、前回の同期以降に端末で変わったグループ・自作語（削除は削除記録＝tombstone として）
  - 受け取る: `cursor` より後にサーバーで変わったグループ・自作語・削除記録と、新しい `cursor`
- 同じレコードが両方で変わっていたら **`updatedAt` が新しい方を採用**（グループの単語の並びはグループ単位でまとめて置き換える）
- 削除の扱いはアプリと同じにする
  - グループの削除: グループだけ消える（単語・自作語は残る）
  - 自作語の削除: グループから外し、端末ではその語の進捗・ログも消す（`GroupEditor.deleteCustomWord`）
- 同期するタイミング: 起動時・アプリに戻ったとき・グループや自作語を変えた少し後・グループ一覧の引っ張って更新。
  通信できなくても端末では普通に編集でき、次につながったときに送る
- 初回の同期では端末にある既存のグループ・自作語をすべて送る。バックアップから復元したときも全件を送り直す

### 管理画面の画面

- **グループ一覧**（`/admin/groups`）: 名前・語数・更新日時。追加・名前の変更・削除（確認あり）
- **グループ詳細**（`/admin/groups/:id`）: 中の単語・フレーズを順番どおりに（英語・意味・品詞・「マイ単語」印）
  - 同梱語を検索して追加（英語・意味で検索 → 結果から追加）。同梱語は表示だけで編集のボタンは出さない
  - 自作語をその場で作って追加（英語・意味は必須、品詞・例文・例文訳は任意。同じ綴りの同梱語があれば案内）
  - 外す・並べ替え（上へ / 下へ）
  - 自作語の編集・削除（削除するとすべてのグループから外れる）
- **マイ単語一覧**（`/admin/custom-words`）: グループに入っていない自作語も含めて一覧・編集・削除

## Phase

1. **サーバーの土台**: `server/` を作る（`handle` と `node:http` のアダプタ・ルーティング・HTML のエスケープ・
   `/health`・Bearer 認証・`ADMIN_ENABLED`・SQLite のマイグレーション）、Vitest、
   Dockerfile の前提を書いた `docs/specs/deploy-g3plus.md`
2. **データと同期 API**: グループ・自作語・削除記録のテーブル、`rev` / `cursor`、`POST /api/sync`
3. **管理画面**: グループ一覧・グループ詳細（同梱語の検索と追加・自作語の作成と編集・外す・並べ替え）・マイ単語一覧
4. **g3plus へデプロイ**: clone・`g3plus-ops/vocab-blossom/` を作って配置、Cloudflare の手作業（ユーザー）、
   `g3plus-ops/docs/workflows/vocab-blossom.md`、g3plus-ops の CLAUDE.md 4 箇所に追記
5. **iOS の同期**: `ServerConfig.plist`・API クライアント・削除記録（SwiftData に追加）・同期のタイミング・
   受け取った変更の反映・設定画面に同期の状態（最後に同期した時刻・エラー）

### Phase 2 の詳細（データと同期 API）

- **テーブル**（マイグレーション 1 本目 `sync-tables`）
  - `groups`（`id` / `name` / `word_ids`（JSON 配列）/ `created_at` / `updated_at` / `rev`）
  - `custom_words`（`word_id` / `word` / `meaning` / `pos` / `example` / `example_ja` / `created_at` / `updated_at` / `rev`）
  - `deletions`（削除記録。`kind`（`group` / `customWord`）+ `id` が主キー / `deleted_at` / `rev`）
  - `sync_meta`（`key` = `rev` に最後に振った通し番号）
  - 生きているレコードと削除記録は同じ ID で同時に存在しない（復活したら削除記録を消す）
- **日時は API でも DB でもミリ秒の整数**（UNIX エポック）。iOS は `JSONDecoder.dateDecodingStrategy = .millisecondsSince1970`。
  ISO 8601 の小数秒の扱いの差で `updatedAt` の比較がずれるのを避ける
- **ID の正規化**: グループの ID は UUID の形式だけ受け付け、小文字にそろえる（Swift の `UUID` は大文字で書き出すため）。
  自作語の ID は `custom-` で始まる文字列
- **ぶつかったときの規則**（`updatedAt` / `deletedAt` の新しい方。同じ時刻なら手元＝サーバーにあるものを残す・削除が勝つ）
  - 更新: サーバーの同じレコードの `updatedAt` 以上、または削除記録の `deletedAt` 以上なら捨てる
  - 削除: サーバーのレコードの `updatedAt` の方が新しければ捨てる
  - 何も変わらないときは `rev` を進めない（同じ内容を 2 回送っても壊れない）
- **自作語の削除はグループからも外す**: その語を含むグループから ID を抜き、グループの `updatedAt` を
  `max(今の updatedAt, deletedAt)` にして `rev` を振る（端末の LWW でもこちらが勝つように）。
  グループを受け取ったときも、削除記録のある自作語の ID は抜いて保存する
  （Phase 5 の iOS 側も `deleteCustomWord` でグループの `updatedAt` を進める）
- **`POST /api/sync`**（Bearer 必須。本文は 5MB まで、超えたら 413。形が違えば 400 で何も保存しない）

  ```jsonc
  // 送る（配列は省略可）
  { "cursor": 0,
    "groups": [{ "id": "uuid", "name": "…", "wordIds": ["…"], "createdAt": 0, "updatedAt": 0 }],
    "customWords": [{ "wordId": "custom-…", "word": "…", "meaning": "…", "pos": "noun",
                      "example": "", "exampleJa": "", "createdAt": 0, "updatedAt": 0 }],
    "deletions": [{ "kind": "group" | "customWord", "id": "…", "deletedAt": 0 }] }
  // 受け取る
  { "cursor": 12, "reset": false, "groups": [...], "customWords": [...], "deletions": [...] }
  ```

  - 1 回の同期は 1 トランザクション。自作語 → グループ → 削除記録の順に当てる
  - 返すのは「`rev` が `cursor` より後のもの」＋「送られてきたレコードのサーバーでの今の状態」（採用されなかった変更も
    サーバーの値で上書きできるように）。`rev` の順
  - `cursor` がサーバーの最新より大きい（サーバーの DB を作り直した）ときは `cursor` = 0 として全件を返し、
    `reset: true` を付ける。端末は全件を送り直す
- **構成**: `server/src/sync/`（`types.ts` 型と入力の検証 / `store.ts` DB の読み書きと LWW / `api.ts` ハンドラ）。
  Phase 3 の管理画面も `store.ts` の同じ関数（`updatedAt` = 今）で書く
- 削除記録は消さない（1 人分なので量は小さい）

Cloudflare の設定は自動化できないので、Phase 4 で手順を出してユーザーに依頼する。
順序は「Access アプリ（`/api` と `/health` の Bypass → ルートの Allow）→ `.env` → Tunnel hostname」。
公開前に `vocab.chobi.me` を DNS で引かない（LAN の DNS が NXDOMAIN を最大 30 分キャッシュする）。

## 影響範囲

- 新規: `server/`、`docs/specs/deploy-g3plus.md`、`ios/VocabBlossom/Resources/ServerConfig.example.plist`
- 変更: `package.json` / `vitest.config.ts` / `tsconfig.json`（server を含める）、
  `.gitignore`（`server/data/`・`ServerConfig.plist`）
- iOS: `GroupEditor`（変更の記録・削除記録）、新規のモデル（削除記録・同期の状態）とサーバー通信・同期、
  `RootView` / `GroupListView`（同期のタイミング）、設定画面、`project.yml`（plist の同梱）、
  `VocabBlossomApp`（ModelContainer に新モデル）、`BackupArchive`（復元後の全件送り直し）
- 別リポジトリ: `~/Projects/g3plus-ops`（デプロイ設定・手順書・CLAUDE.md）

## テスト方針

- サーバー（Vitest）
  - 認証: Bearer なし・違う → 401、`ADMIN_ENABLED` 未設定なら `/admin` は 404
  - ルーティング: パスのパラメータ・未定義のパスは 404・メソッド違いは 405
  - HTML: 単語の意味や例文に `<script>` などを入れてもエスケープされる、`Origin` が違う POST は 403
  - 同期: 端末の変更が保存される・管理画面の変更が `cursor` 以降として返る・ぶつかったら新しい方・
    削除記録が届く・同じ内容を 2 回送っても壊れない
  - 管理画面: グループの追加・名前変更・削除、語の追加・外す・並べ替え、自作語の作成・編集・削除（グループからも外れる）
- iOS（Swift Testing。通信は `URLProtocol` のスタブ）
  - `ServerConfig.plist` が無ければ通信しない、通信に失敗しても学習・編集は今までどおり動く
  - 送る差分（前回以降の変更・削除記録）、受け取った変更の反映（グループ・自作語の作成・更新・削除。
    自作語の削除で進捗・ログも消える）
- デプロイ後の疎通確認（curl）: `/api/*` は Bearer なしで 401・ありで 200、`/admin` は Access のログインへ（302）、`/health` は 200
- 既存テスト・SwiftLint 警告 0
- 実機で確認: 管理画面でグループを作る → アプリに出る、アプリで語を足す → 管理画面に出る、削除が双方に届く
