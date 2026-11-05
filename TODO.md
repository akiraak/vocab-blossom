# TODO

- [ ] グループの単語をすべて読み上げる機能を入れる（ループ再生もできるようにする。読むのは単語 → 意味 → 例文 → 例文の和訳。画面を消しても鳴らし、ほかのアプリの音は止める）→ [plan](docs/plans/group-read-aloud.md)
  - [x] Phase 0: 何を読むか・画面を消しても鳴らすかなどを決める
  - [x] Phase 1: 読み上げの仕組み（`ReadAloudPlayer`。再生・一時停止・前後・ループ）
  - [x] Phase 2: 読み上げ画面とグループ詳細のボタン
  - [x] Phase 3: 画面を消しても鳴らす（バックグラウンド再生・ロック画面の操作）
  - [ ] Phase 4: 実機確認
- [ ] 読み上げの声を Gemini TTS にする（esl-speaking-coach の Chobi / Naruko の声を持ってくる）→ [plan](docs/plans/read-aloud-gemini-voice.md)
  - [x] Phase 0: 声（2 人分作ってランダム）・音声を作る場所（サーバー）を決める
  - [x] Phase 1: 試聴して声と前置文を決める
  - [x] Phase 2: サーバー（`POST /api/speech`）
  - [x] Phase 3: iOS（声の差し替え・端末に残す・先読み・内蔵 TTS への切り替え）
  - [ ] Phase 4: 実機確認
- [ ] AI のモデルを iOS の設定画面で選べるようにする（Claude は Opus 5.5 / Sonnet 5.5、TTS は Gemini 3.8 Flash / Flash-Lite）→ [plan](docs/plans/ai-model-settings.md)
  - [x] Phase 1: サーバー（リクエストの `model` を許可リストで受け付ける）
  - [x] Phase 2: iOS（設定画面・リクエストに `model` を付ける・読み上げの置き場をモデルごとに）
  - [ ] Phase 3: デプロイ・実機確認
