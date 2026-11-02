# TODO

- [ ] vocab-blossom 用の管理画面（Web）を作る [plan](docs/plans/admin-server.md)
  - グループの追加・名前変更・削除と、グループ内の単語・フレーズの追加・外す・編集（アプリと同期）
  - Claude API キーは管理画面の起動時の環境変数（`ANTHROPIC_API_KEY`）で渡す（アプリには埋め込まない）
  - g3plus-ops 経由で `vocab.chobi.me` に配置する
  - [x] Phase 1: サーバーの土台（`server/`・フレームワーク無しの `node:http`・Bearer 認証・`ADMIN_ENABLED`・SQLite・デプロイ契約）
  - [x] Phase 2: データと同期 API（グループ・自作語・削除記録、`POST /api/sync`）[plan](docs/plans/admin-server.md#phase-2-の詳細データと同期-api)
  - [x] Phase 3: 管理画面（グループ一覧・グループ詳細・マイ単語一覧）[plan](docs/plans/admin-server.md#phase-3-の詳細管理画面)
  - [ ] Phase 4: g3plus へデプロイ（clone・g3plus-ops・Cloudflare の手作業。port 3015）[plan](docs/plans/admin-server.md#phase-4-の詳細g3plus-へデプロイ)
  - [ ] Phase 5: iOS の同期（`ServerConfig.plist`・削除記録・同期のタイミング・設定画面に同期の状態）
- [ ] 辞書にない単語を登録するときに AI でタイポチェックを行う（管理画面のサーバー経由で Claude API を呼ぶ。管理画面の完成後）
