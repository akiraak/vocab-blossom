# TODO

- 単語データの整備（CEFR A1〜A2 デッキ + 基礎熟語の JSON 作成）[plan](docs/plans/word-data.md)
  - [x] 出典候補のライセンス調査と採用判断（→ docs/specs/word-data.md）
  - [x] データスキーマ設計（src/data/types.ts、デッキ JSON 構成）
  - [x] A1 デッキ生成（1,012 語）
  - [x] A2 デッキ生成（1,231 語）
  - [x] 基礎熟語デッキ生成（200 フレーズ）
  - [x] データ検証テスト（Vitest）
  - [ ] 訳・例文の人手レビュー
- MVP 実装（レベル選択オンボーディング、学習/復習ループ、庭ビジュアル、単語帳一覧、統計、設定）
- iOS アプリ実装（MVP の PWA 検証後。方式は要検討: Capacitor でのラップ / React Native / Swift ネイティブ）
