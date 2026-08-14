# vocab-blossom

覚えた単語が花になって庭が育つ、英語初学者（CEFR A1〜A2）向けの単語学習 iOS アプリ。

コンセプトの詳細は [docs/specs/app-concept.md](docs/specs/app-concept.md) を参照。

> 2026-08-14 に Web/PWA から iOS ネイティブ（SwiftUI）へ全面移行した。
> 経緯と実装計画は [docs/plans/ios-native-migration.md](docs/plans/ios-native-migration.md) を参照。
> アプリ本体（`ios/`）は Phase 1 で追加する。

## 技術スタック

- SwiftUI + Observation / SwiftData（Deployment Target: iOS 18.0）
- AVSpeechSynthesizer（TTS）
- XcodeGen + SwiftLint
- 単語データ整備: Python（CEFR-J からの抽出）+ Vitest（データ内容の検証）

## 開発

```bash
npm install
npm test         # 単語データの内容検証 (Vitest)
```

単語データは `src/data/decks/*.json`（Phase 1 で `data/decks/` へ移動予定）。整備・レビュー手順は [docs/specs/word-data.md](docs/specs/word-data.md) を参照。
