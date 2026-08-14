# vocab-blossom

覚えた単語が花になって庭が育つ、英語初学者（CEFR A1〜A2）向けの単語学習 iOS アプリ。

コンセプトの詳細は [docs/specs/app-concept.md](docs/specs/app-concept.md) を参照。

> 2026-08-14 に Web/PWA から iOS ネイティブ（SwiftUI）へ全面移行した。
> 経緯と実装計画は [docs/plans/ios-native-migration.md](docs/plans/ios-native-migration.md) を参照。

## 技術スタック

- SwiftUI + Observation / SwiftData（Deployment Target: iOS 18.0、iPhone 縦向き専用）
- AVSpeechSynthesizer（TTS）
- XcodeGen + SwiftLint
- 単語データ整備: Python（CEFR-J からの抽出）+ Vitest（データ内容の検証）

## ディレクトリ

```
ios/          アプリ本体（project.yml から Xcode プロジェクトを生成する）
data/decks/   単語 JSON（アプリへフォルダ参照で同梱）
data/source/  CEFR-J 元データ
scripts/      単語データ整備スクリプト（Python）
src/          単語データの内容検証テスト（Vitest）のみ
docs/         仕様・プラン
```

## 開発

### iOS アプリ

```bash
cd ios
xcodegen generate          # VocabBlossom.xcodeproj を生成（.gitignore 対象）
open VocabBlossom.xcodeproj

# コマンドラインでのビルド / テスト
xcodebuild -project VocabBlossom.xcodeproj -scheme VocabBlossom \
  -destination 'platform=iOS Simulator,name=iPhone 17' build test
```

### 単語データ

```bash
npm install
npm test         # 単語データの内容検証 (Vitest)
```

単語データは `data/decks/*.json`。整備・レビュー手順は [docs/specs/word-data.md](docs/specs/word-data.md) を参照。
