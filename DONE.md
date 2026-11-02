# DONE

- 2026-11-02 グループを作成し単語やフレーズを登録し、そのグループ単位で学習できるようにする（新タブ「グループ」。同梱語を単語帳から選ぶ / 英語・意味・品詞・例文を入力して自作語を作る、の 2 通りで登録。グループ詳細から「学習する」（グループ内の期限到来の復習 + 未学習語を追加順に。SRS 共有で庭・毎日の復習にも反映）と「ドリル」（全語ランダムの 4 択、進捗・ログを残さない、間違えた語を締めで表示）。単語帳に「マイ単語」チップ、単語詳細にグループ出し入れ・自作語の編集削除。バックアップ形式 v2 でグループ・自作語も書き出し（v1 も読込可）。Swift Testing 132 件・SwiftLint 警告 0・シミュレータで確認）→ [plan](docs/plans/archive/word-groups.md)
- 2026-08-19 問題回答時の正解と不正解にわかりやすい音を入れる（クイズ番組式のピンポン / ブッブーをコードで PCM 合成して `AVAudioPlayer` で再生。回答の瞬間に鳴らし、単語の読み上げは 0.5 秒遅らせて重ねない。設定に「正解・不正解の音」トグルを追加し読み上げとは独立にオフにできる）→ [plan](docs/plans/archive/answer-feedback-sounds.md)
- 2026-08-13 どのようなアプリにするか考える → [docs/specs/app-concept.md](docs/specs/app-concept.md)
- 2026-08-13 技術スタックのセットアップ（Vite + React + TypeScript + Tailwind v4 + vite-plugin-pwa + Vitest。ビルド・テスト・dev サーバー起動を確認済み）→ [plan](docs/plans/archive/tech-setup.md)
- 2026-08-14 単語データの整備（CEFR A1〜A2 デッキ 2,243 語 + 基礎熟語 200 の JSON 作成）→ [plan](docs/plans/archive/word-data.md) / [spec](docs/specs/word-data.md)
- 2026-08-14 訳・例文のレビュー（全 2,443 件を LLM 第 2 パスで点検し 137 エントリを修正。内容チェックを Vitest に追加）→ [plan](docs/plans/archive/word-review.md) / [spec §5](docs/specs/word-data.md)
- 2026-08-14 既知語の一括スキップと 1 日の学習量の引き上げ（「もう知ってる」を開花扱いにして復習を増やさず片付けられるように。既知語をまとめて選ぶ画面をオンボーディング・設定に追加。新規語を最大 100 語/日まで拡張し、復習上限は新規語 × 6 で自動追従）→ [plan](docs/plans/archive/known-words-and-daily-volume.md)
- 2026-08-14 iOS ネイティブ実装（SwiftUI で MVP を一通り実装。オンボーディング / ホーム（庭・ストリーク）/ 学習・復習セッション（4 形式・再出題）/ 単語帳・単語詳細 / 統計 / 設定（エクスポート・インポート）。Swift Testing 80 件・SwiftLint 警告 0・シミュレータで動作確認）→ [plan](docs/plans/archive/ios-native-migration.md)
- 2026-08-16 出題順がABC順になっているのでランダムにする（単語 ID と端末ごとの種から並びを決める `ShuffleOrder` を追加。新規学習プールはレベル内をまるごとシャッフル、復習は期限順に選んで出題順はシャッフル。同じ端末なら並びは毎回同じなのでホームの表示・中断再開とずれない）→ [plan](docs/plans/archive/random-question-order.md)
- 2026-08-13 コンセプトの未決事項を決める → 推奨案どおり確定（[app-concept §8](docs/specs/app-concept.md): 同期は MVP ローカル + エクスポート/インポート、単語データは LLM 生成 + 人手レビュー、新規語 10 語/日、収録は A1〜A2）
