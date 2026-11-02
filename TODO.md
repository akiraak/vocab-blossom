# TODO

- [ ] vocab-blossom 用の管理画面（Web）を作る
  - 単語（同梱語・自作語）の編集なども行えるようにする
  - Claude API キーは管理画面の起動時の環境変数（`ANTHROPIC_API_KEY`）で渡す（アプリには埋め込まない）
  - g3plus-opt 経由で `xxxx.chobi.me` に配置する（サブドメインは未定）
- [ ] 辞書にない単語を登録するときに AI でタイポチェックを行う（管理画面のサーバー経由で Claude API を呼ぶ。管理画面の完成後）
