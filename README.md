# vocab-blossom

覚えた単語が花になって庭が育つ、英語初学者（CEFR A1〜A2）向けの単語学習 iOS アプリ。

コンセプトの詳細は [docs/specs/app-concept.md](docs/specs/app-concept.md) を参照。

> 2026-08-14 に Web/PWA から iOS ネイティブ（SwiftUI）へ全面移行した。
> 経緯と実装計画は [docs/plans/archive/ios-native-migration.md](docs/plans/archive/ios-native-migration.md) を参照。

## 技術スタック

- SwiftUI + Observation / SwiftData（Deployment Target: iOS 18.0、iPhone 縦向き専用）
- AVSpeechSynthesizer（TTS）/ Swift Charts（統計）
- XcodeGen + SwiftLint + Swift Testing
- 単語データ整備: Python（CEFR-J からの抽出）+ Vitest（データ内容の検証）

外部ライブラリへの依存はなし（SPM パッケージを追加していない）。

## ディレクトリ

```
ios/
  project.yml           XcodeGen 定義（.xcodeproj は生成物なので Git に入れない）
  VocabBlossom/
    App/                エントリポイント、ルート TabView、デバッグ用シード
    Core/               DateUtil / SRS / Inflector / QuizBuilder / SessionBuilder /
                        Dashboard / LearningEngine / WordStore / AppSettings /
                        SpeechService / BackupArchive / Theme
    Models/             WordEntry・Deck（JSON）/ WordProgress・AnswerLog（SwiftData）
    Features/           Onboarding / Home / Session / WordList / Stats / Settings
    Resources/          Assets.xcassets
  VocabBlossomTests/
data/decks/             単語 JSON（アプリへフォルダ参照で同梱）
data/source/            CEFR-J 元データ
scripts/                単語データ整備（Python）、アプリアイコン生成（Swift）
src/                    単語データの内容検証テスト（Vitest）のみ
docs/                   仕様・プラン
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

swiftlint                  # ios/ で実行（警告 0 を維持する）
```

### 実機で動かす

リポジトリ直下の `run-ios-device.sh` が「プロジェクト生成 → ビルド → インストール → 起動」まで行う。

```bash
./run-ios-device.sh
IOS_DEVICE="AkiraのiPhone" ./run-ios-device.sh   # 端末を指定する
IOS_CONSOLE=1 ./run-ios-device.sh                # 起動後にログを流す
```

- iPhone のロックを解除しておく（ロック中は起動できない）
- 署名チームは `DEVELOPMENT_TEAM` 環境変数で差し替えられる（既定は手元の Apple Development 証明書のチーム）
- Xcode がプロビジョニングの更新を求めるときは Xcode > Settings > Accounts でのログインが必要

### 画面確認用のダミーデータ（DEBUG ビルドのみ）

環境変数を渡すと、学習途中の状態を作った上で目的の画面を開いた状態で起動できる。

```bash
SIMCTL_CHILD_VOCAB_SEED_DEMO=1 SIMCTL_CHILD_VOCAB_DEMO_SCREEN=session \
  xcrun simctl launch booted com.akiraak.VocabBlossom
```

`VOCAB_DEMO_SCREEN` は `session` / `session-new` / `session-summary` /
`words` / `stats` / `settings` / `fresh` を指定できる（詳細は `App/DebugSeed.swift`）。

### アプリアイコン

```bash
swift scripts/make-appicon.swift   # 1024x1024 PNG を Assets.xcassets へ書き出す
```

### 単語データ

```bash
npm install
npm test         # 単語データの内容検証 (Vitest)
```

単語データは `data/decks/*.json`。整備・レビュー手順は [docs/specs/word-data.md](docs/specs/word-data.md) を参照。
