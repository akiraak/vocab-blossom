# g3plus デプロイ契約

vocab-blossom の管理画面とアプリ同期のサーバー（`server/`）を g3plus（自宅サーバ）で動かすための契約。
デプロイ設定の正本は `g3plus-ops/vocab-blossom/`（`docker-compose.yml` / `Dockerfile` / `.env` / `.env.example`）。
運用手順は `g3plus-ops/docs/workflows/vocab-blossom.md`。**契約が変わったらそちらを追従させる。**

全体の設計は [docs/plans/archive/admin-server.md](../plans/archive/admin-server.md)。

## 契約

- **置き先のサーバ**: g3plus（`g3plus.lan`。Tunnel は `g3plus`）
- **リポジトリ**: https://github.com/akiraak/vocab-blossom（**public**）。g3plus 上に
  `/home/ubuntu/vocab-blossom/` として clone し build context にする。更新は `git pull` → rebuild
- **Node**: 24（TypeScript を **型除去でそのまま起動**するため 24 以上が必須。ビルド工程・tsx なし）。
  better-sqlite3 のネイティブ ABI を Dockerfile の deps / runtime の各ステージで一致させる
- **依存のインストール**: `server/` で `npm ci --omit=dev`（`server/package.json` / `server/package-lock.json`。
  ルートの `package.json` はテスト用でイメージには不要）
- **COPY 対象**: コンテナ内はリポジトリと同じ並びにする（同梱語の検索で `data/decks/` を読むため）
  - `server/package.json` / `server/package-lock.json` / `server/src/` → `/app/server/`
  - `data/decks/` → `/app/data/decks/`
- **起動**: `WORKDIR /app` で `node server/src/main.ts`。SIGTERM で受付をやめて DB を閉じて終わる
- **ポート**: 3015（コンテナ内。ホストへは**非公開**、`n8n_default` ネットワークの cloudflared からだけ届く）
- **必須 env**（`g3plus-ops/vocab-blossom/.env`）:
  - `API_SHARED_SECRET` — iOS の `/api/*` を守る共有シークレット（`openssl rand -hex 32`）。
    iOS の `ServerConfig.plist` の `API_KEY` と揃える。**未設定ならサーバーは起動しない**
  - `VOCAB_DB_PATH=/app/server/data/vocab-blossom.db`
- **任意 env**:
  - `ADMIN_ENABLED=on` — 管理画面（`/admin/*`）を有効にする。`on` 以外・未設定なら `/admin/*` はすべて 404（fail-safe）。
    Cloudflare Access を設定し終えてから `on` にする
  - `ANTHROPIC_API_KEY` — Claude API。自作語を作る前の AI チェック（`POST /api/word-assist`・`POST /admin/word-assist`。
    打ち間違い・変化形を同梱語に寄せ、無い語は意味・例文を下書き）に使う。未設定なら AI チェックだけ 503 で、他の機能は動く
  - `ANTHROPIC_MODEL` — AI チェックのモデル（既定 `claude-opus-5-5`。安くしたいときは `claude-haiku-5-5` など）
  - `PORT` — 既定 3015
- **永続化**: SQLite（`VOCAB_DB_PATH` のディレクトリ）。volume `/home/ubuntu/vocab-blossom/server/data:/app/server/data`。
  `/app/data` は同梱の単語 JSON の置き場所なので volume にしない。
  DB の版は `PRAGMA user_version` で管理し、起動時に未適用のマイグレーションを当てる
  （DB の方が新しい版なら起動しない = 古いイメージへ戻すときは DB のバックアップも戻す）
- **ヘルスチェック**: `GET /health` → `200 {"ok":true}`（認証なし）
- **ログ**: 標準出力に 1 リクエスト 1 行（`GET /admin/groups 200 3ms`。クエリは出さない）、例外は標準エラー
- **TZ**: America/Los_Angeles（g3plus 既定）

## 認証

| パス | アプリ側 | Cloudflare Access |
| --- | --- | --- |
| `/api/*`（iOS 用） | `Authorization: Bearer <API_SHARED_SECRET>`（無い・違うと 401） | Bypass（Everyone） |
| `/admin/*`（管理画面） | `ADMIN_ENABLED=on` のときだけ有効。POST などは `Origin` のホストが `Host` と一致しないと 403 | Allow（Google IdP / Emails） |
| `/health` | なし | Bypass |

- `/api/word-assist` と `/admin/word-assist` は合わせてサーバー全体で 10 分に 60 回まで（超えると 429）。
  iOS に入れた共有シークレットが漏れても Claude API の請求が膨らまないようにするため

- cloudflared は **Host ヘッダを書き換えない**こと（`originRequest.httpHostHeader` を設定しない）。
  管理画面の `Origin` 確認が `Host` と比べるため
- トレードオフ: origin に直接届く相手（同じ Docker ネットワークのコンテナ）には管理画面が無認証になる
  （trip-note と同じ整理。ホストポートは非公開にしてある）

## Cloudflare（akiraak の手作業）

ホスト名: `vocab.chobi.me`（2026-11-02 設定済み・公開）

順序は「Access → `.env` → Tunnel hostname」。公開前に `vocab.chobi.me` を DNS で引かない
（LAN の DNS が NXDOMAIN を最大 30 分キャッシュする）。

1. **Access（3 アプリケーション）**:
   - `vocab.chobi.me/api` → **Bypass**（Everyone）。API 自体が Bearer で認証する
   - `vocab.chobi.me/health` → **Bypass**（Everyone）
   - `vocab.chobi.me` → **Allow**（Google IdP / Emails）。管理画面の認証
2. `.env` に `ADMIN_ENABLED=on` を入れて `up -d`
3. **Tunnel hostname**（tunnel `g3plus`）: `vocab.chobi.me` → `http://vocab-blossom:3015`

## ローカルで動かす

```bash
(cd server && npm install)
API_SHARED_SECRET=dev ADMIN_ENABLED=on npm run server:dev   # http://localhost:3015/admin
```

DB は既定で `server/data/vocab-blossom.db`（git 管理外）。

## デプロイ後の疎通確認

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://vocab.chobi.me/health              # 200
curl -s -o /dev/null -w '%{http_code}\n' https://vocab.chobi.me/api/ping            # 401
curl -s -H "Authorization: Bearer $API_SHARED_SECRET" https://vocab.chobi.me/api/ping  # {"ok":true}
curl -s -o /dev/null -w '%{http_code}\n' https://vocab.chobi.me/admin/groups        # 302（Access のログインへ）
```
