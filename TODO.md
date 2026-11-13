# TODO

- [ ] 穴埋めで単語をキー入力するモードを入れる（「穴埋め」のあと 4 択か入力かを選ぶ。問題はどちらも始めるたびに作り直し、同じ文章を出さない） [plan](docs/plans/fill-blank-typing.md)
  - [x] Phase 1: 問題と判定（`Quiz` の答え方・正解の綴り、`QuizBuilder`）
  - [ ] Phase 2: 文章の作り直し（サーバーの `POST /api/passages` に `refresh`。コードは済み。g3plus へのデプロイが残り）
  - [x] Phase 3: 進行（`SessionRunner` の入力の回答、グループの記録）
  - [x] Phase 4: 画面（答え方を選ぶ画面、補完を切った入力欄、全語の作り直し、シミュレータで確認）
  - [ ] Phase 5: iPhone で確認（ユーザー）と後片付け
