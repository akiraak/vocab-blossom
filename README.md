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
src/                    単語データの内容検証テスト（Vitest）
server/                 管理画面（Web）とアプリ同期のサーバー（Node 24 + TypeScript、node:http）
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

### 管理画面サーバーとの同期

グループと自作語は管理画面のサーバー（`vocab.chobi.me`）と同期する（学習の記録は端末の中だけ）。
接続先は `ios/VocabBlossom/Resources/ServerConfig.plist`（**git 管理外**。リポジトリが public なので API キーはコミットしない）。

```bash
cp ios/VocabBlossom/Resources/ServerConfig.example.plist ios/VocabBlossom/Resources/ServerConfig.plist
# BASE_URL と API_KEY（サーバーの API_SHARED_SECRET）を入れてから xcodegen generate / ./run-ios-device.sh
```

- ファイルが無ければ同期せず、端末の中だけで動く。テストの実行中と、`VOCAB_SEED_DEMO=1` でダミーデータを
  入れたことのある端末（アプリを入れ直すまで）も同期しない
- plist を置いた・消したときは `xcodegen generate` をやり直す（プロジェクトにファイルの参照が入るため）
- ローカルのサーバーで試すときは `BASE_URL` を `http://<Mac の IP>:3015`（シミュレータなら `http://127.0.0.1:3015`）にする
- 仕組みは [docs/plans/archive/admin-server.md](docs/plans/archive/admin-server.md) の「Phase 5 の詳細」

### 画面確認用のダミーデータ（DEBUG ビルドのみ）

環境変数を渡すと、学習途中の状態を作った上で目的の画面を開いた状態で起動できる。

```bash
SIMCTL_CHILD_VOCAB_SEED_DEMO=1 SIMCTL_CHILD_VOCAB_DEMO_SCREEN=session \
  xcrun simctl launch booted com.akiraak.VocabBlossom
```

`VOCAB_DEMO_SCREEN` は `session` / `session-summary` /
`my-words` / `stats` / `settings` / `fresh` / `onboarding` など、グループの画面も含めて指定できる（詳細は `App/DebugSeed.swift`）。

### アプリアイコン

```bash
swift scripts/make-appicon.swift   # 1024x1024 PNG を Assets.xcassets へ書き出す
```

### 単語データ

```bash
npm install
npm test         # 単語データの内容検証 + サーバーのテスト (Vitest)
```

単語データは `data/decks/*.json`。整備・レビュー手順は [docs/specs/word-data.md](docs/specs/word-data.md) を参照。

### 管理画面のサーバー

Node 24 が必要（`.node-version`。better-sqlite3 のネイティブモジュールを Node 24 でビルドするため、
`npm test` も Node 24 で動かす）。

```bash
(cd server && npm install)
API_SHARED_SECRET=dev ADMIN_ENABLED=on npm run server:dev   # http://localhost:3015/admin
```

デプロイ契約（env・ポート・永続化先）は [docs/specs/deploy-g3plus.md](docs/specs/deploy-g3plus.md)、
全体のプランは [docs/plans/archive/admin-server.md](docs/plans/archive/admin-server.md)。

- シェルの既定の Node が 20 のままだと、better-sqlite3 が読めずにテストが落ちる。Node は fnm で入れてあるので、
  `eval "$(fnm env)" && fnm exec --using=24 npm test`（型チェックは `npm run typecheck`）のように 24 を指定して動かす

### Claude Code で作業するときの注意（macOS の「アプリ管理」と node）

Claude Code は `node` の上で動くため、Claude Code が実行したコマンドは macOS から `node` の操作として扱われる。
ほかのアプリ（`.app`）の中身を書き換えようとすると、「プライバシーとセキュリティ: "node" によるアプリ変更が Mac で阻止されました」と出る。

- 2026-11-03、iOS アプリのビルド・テストと、管理画面のスクリーンショットを撮るために Google Chrome をヘッドレスで起動した作業の中で出た。
  どちらが原因かは特定できていない（Chrome の自動更新が走った可能性がある）。止められても、ビルド・テスト・スクリーンショットはすべて終わっていた
- システム設定 > プライバシーとセキュリティ > アプリ管理の `node` は **オフのままにする**。オンにすると Claude Code に限らず、
  `node` で動くあらゆるスクリプトがほかのアプリを書き換え・削除できるようになる
- 実機への書き込み（`./run-ios-device.sh`）など、必要な操作がこの保護で失敗したときだけ、一時的にオンにする
- 画面の確認に Chrome をヘッドレスで起動するのは控え、管理画面は Chrome 拡張、iOS はシミュレータで見る
