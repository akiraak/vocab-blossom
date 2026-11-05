# TODO

- [ ] 接続詞・つなぎの語句（94 語）を働き（時・条件・逆接・理由・目的など）ごとに 10 のグループに分けて登録する（穴埋めの検証の前にやる）→ [plan](docs/plans/connective-groups.md)
  - [x] Phase 1: グループ分けとマイ単語 70 語の下書き（`data/groups/connectives.json`）
  - [x] Phase 2: JSON を取り込むスクリプト（`server/src/import-groups.ts`）
  - [ ] Phase 3: 本番に取り込んで、iPhone で同期して確認する
- [ ] グループに接続詞・つなぎの語句（if, when, first, finally, so that など）を入れても、穴埋めの文章が問題なく作れるか検証し、ダメなら直す（品詞 `conjunction` はサーバー・iOS とも既にある。first / finally は副詞、so that は熟語の扱いになりそう）。同じ働きのグループで 4 択・穴埋めの正解が複数にならないかも見る（[plan](docs/plans/connective-groups.md) の「3. 同じグループに似た意味の語が入ることへの対処」）
- [ ] 実機確認（2026-11-04 に実装した読み上げ・AI のモデル選択。まとめて行う。おかしければ別タスクにする）
  - [x] 読み上げ: 最後まで読む・ループ・一時停止と再開・前後・割り込み（電話・ほかのアプリの音楽）・ロック中の再生とロック画面からの操作・日本語の速さ（2026-11-04 問題なし）→ [plan](docs/plans/archive/group-read-aloud.md)
  - [x] 読み上げの声（Gemini）: 声・速さ・日本語の自然さ、スピーカーで割れないこと、オフラインで内蔵の声に落ちること（2026-11-04 問題なし）→ [plan](docs/plans/archive/read-aloud-gemini-voice.md)
  - [x] 読み上げの待ち時間: グループ詳細を開いてから読み上げを押すとすぐ鳴る・2 語目の頭で待たない（2026-11-04 問題なし）→ [plan](docs/plans/archive/read-aloud-start-delay.md)
  - [ ] AI のモデル: 設定画面から切り替えて、AI チェック・穴埋め・読み上げが動く → [plan](docs/plans/archive/ai-model-settings.md)
