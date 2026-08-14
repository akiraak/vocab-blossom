# TODO

- iOS ネイティブ実装（SwiftUI。Web/PWA からの全面移行）[plan](docs/plans/ios-native-migration.md)
  - [x] Phase 1: プロジェクト基盤（XcodeGen、単語 JSON 同梱、SwiftData、設定、TTS、TabView 骨格、Web 資産の削除）
  - [x] Phase 2: コアロジック移植（日付/SRS/クイズ生成/セッション構築 + 単体テスト）
  - [x] Phase 3: オンボーディング + ホーム（庭・ストリーク）
  - [x] Phase 4: 学習/復習セッション（提示カード・4 形式クイズ・再出題・締め画面）
  - [x] Phase 5: 単語帳一覧・単語詳細
  - [ ] Phase 6: 統計・設定（エクスポート/インポート）
  - [ ] Phase 7: 仕上げ（アイコン、実機確認、Dynamic Type / VoiceOver、SwiftLint）
- 端末間の進捗同期（PC / 複数端末で使うようになったら。MVP はエクスポート/インポートのみ）
