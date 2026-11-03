# TODO

- [ ] 辞書にない単語を登録するときに AI でタイポチェックを行い、意味・品詞・例文も AI で下書きして同梱語に無い語の追加を極力減らす（管理画面のサーバー `vocab.chobi.me` に API を 1 本足して Claude API を呼ぶ）→ [plan](docs/plans/ai-word-assist.md)
  - [x] Phase 1: サーバーの `POST /api/word-assist`（AI 呼び出し・同梱語との照合・回数制限・テスト）
  - [x] Phase 2: iOS の自作語エディタに AI チェック
  - [x] Phase 3: 管理画面のフォームに AI チェック
  - [ ] Phase 4: g3plus へ反映（`ANTHROPIC_API_KEY` を設定して再ビルド）
