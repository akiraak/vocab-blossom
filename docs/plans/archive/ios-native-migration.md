# iOS ネイティブ実装への全面移行プラン

作成日: 2026-08-14

## 目的・背景

MVP の実装形態を **Web/PWA（Vite + React）から iOS ネイティブ（SwiftUI）へ全面移行**する。
[app-concept §7](../specs/app-concept.md) では「ネイティブは MVP 検証段階ではコストに見合わない」として
PWA を採用していたが、方針変更により MVP からネイティブで作る。

これにより以下が変わる:

- 進行中だった [mvp-implementation](archive/mvp-implementation.md)（React 版 Phase 1〜6）は中止し、本プランで置き換える
- PC 対応は当面あきらめる（iPhone のみ）。app-concept §2 の「iPhone と PC の両方」は iPhone 優先に見直す
- 端末間同期（§8-1）は単一端末の間は不要になり、優先度が下がる

移行しても**単語データ（2,443 語）・SRS 仕様・出題形式・画面構成といった設計判断はそのまま流用できる**ため、
実質的な作り直しは UI と永続化層に限られる。

## 前提環境（2026-08-14 時点で確認済み）

- Xcode 26.5 (17F42) / Apple Swift 6.3.2 / iOS 26.5 SDK・Simulator
- `xcodegen` / `swiftlint` は Homebrew で導入済み

## 対応方針

### 技術選定

| 領域 | 採用 | 理由 |
|---|---|---|
| UI | SwiftUI | 画面数が少なく宣言的 UI で足りる。庭ビジュアルも Canvas / Shape で描ける |
| 状態管理 | Observation (`@Observable`) | iOS 17+ の標準。外部ライブラリ不要 |
| 永続化 | SwiftData | 進捗・回答ログのみで要件が単純。SwiftUI との統合が楽 |
| 設定 | `UserDefaults` (`@AppStorage`) | Web 版 localStorage と同じ役割 |
| 音声 | `AVSpeechSynthesizer` | Web Speech API の置き換え。en-US 固定、追加コストなし |
| テスト | Swift Testing | Xcode 26 標準。純ロジックの単体テストに使う |
| プロジェクト生成 | XcodeGen (`project.yml`) | `.pbxproj` を手で管理せず、差分を読める形でリポジトリに残す |
| Lint | SwiftLint | 導入済みのため最小ルールで有効化 |

外部ライブラリへの依存は追加しない（SPM パッケージなし）。

- **Deployment Target: iOS 18.0**（SwiftData / Observation を使うのに十分で、実機の対応範囲も広い）
- **対応デバイス: iPhone のみ**（縦向き固定。iPad・Mac Catalyst は将来）

### リポジトリ構成

Web 由来のファイルと混ざらないよう、アプリ本体は `ios/` 配下にまとめる。

```
ios/
  project.yml                  # XcodeGen 定義
  VocabBlossom.xcodeproj       # 生成物（.gitignore に入れる）
  VocabBlossom/
    App/                       # エントリポイント、ルート TabView
    Core/                      # DateUtil, SRS, QuizBuilder, SessionBuilder, Speech
    Models/                    # WordEntry, Deck, Progress, AnswerLog, Settings
    Features/                  # Onboarding, Home, Session, WordList, Stats, Settings
    Resources/                 # Assets, decks/*.json（data/decks へのフォルダ参照）
  VocabBlossomTests/
data/
  source/                      # CEFR-J 元データ（変更なし）
  decks/                       # 単語 JSON（src/data/decks から移動）
scripts/                       # データ整備（Python。出力先パスのみ更新）
docs/
```

### 既存 Web 資産の扱い

**残す**（単語データの整備・検証パイプラインは Node/Python のままが早い）:

- `data/source/`・`scripts/*.py`
- 単語 JSON（`src/data/decks/` → `data/decks/` へ移動。`scripts/apply-review.py` の `DECK_DIR` を追従）
- `src/data/decks.test.ts`・`src/data/types.ts`・`src/lib/inflect.ts`（データ内容検証テスト。Vitest のまま維持）
  - `inflect.ts` は活用形照合に 227 行の作り込みがあり、Swift へ移す実利がない。
    穴埋めクイズ用の空欄化は、この検証で「例文が見出し語を含む」ことが保証済みなので、
    アプリ側は素朴な正規表現マッチ + 失敗時は英→日にフォールバックで足りる

**削除**（Swift へ移植 or 不要）:

- `src/App.tsx`・`src/App.test.tsx`・`src/main.tsx`・`src/index.css`・`src/vite-env.d.ts`
- `src/lib/date.ts`・`src/lib/srs.ts`・`src/lib/words.ts`（ロジックは Swift へ移植）
- `index.html`・`public/`・`dist/`・`vite.config.ts`・`tsconfig.app.json`
- `package.json` から React / Vite / Tailwind / PWA / Testing Library 系の依存（Vitest とデータ検証だけ残す）

削除は Phase 1 の最後にまとめて行い、それまでは参照用に残す。

### データモデル（SwiftData）

Web 版プランの設計をそのまま移す。

- `WordProgress`（`wordId` が `@Attribute(.unique)`）: `stage(1〜5)` / `dueAt: Date` / `learnedAt: Date` /
  `updatedAt: Date` / `known: Bool`
  - **レコードが無い単語 = 種（stage 0、未学習）**とし、種のレコードは作らない
- `AnswerLog`: 1 回答 1 行（`wordId` / `answeredAt: Date` / `dateKey: String` / `correct: Bool` /
  `quizType` / `kind(review|new|requeue)` / `stageAfter`）。統計・ストリークはここから導出する
- 単語データ本体は SwiftData に入れず、起動時に JSON をデコードしてメモリ上のインデックス
  （`WordStore`）で保持する（2,443 件・約 600KB。全文検索も線形で足りる）
- 設定は `@AppStorage`: `level` / `newWordsPerDay`(10) / `reviewLimitPerDay`(60) / `soundEnabled`

### SRS（Leitner）

Web 版 `src/lib/srs.ts` と同一仕様を Swift へ移植する。

- ステージ到達時の次回間隔: 1 → +1日 / 2 → +3日 / 3 → +1週間 / 4 → +2週間 / 5(開花) → +1ヶ月、
  開花後の維持復習は +3ヶ月
- 復習正解: stage +1（最大 5。5 で正解したら 5 のまま維持間隔）
- 不正解: stage −1（最低 1 = 芽）、翌日再復習にスケジュールし、セッション末尾に再出題（同一カード 2 回まで）。
  再出題での正誤はステージ・スケジュールを変えない
- 新規学習の直後クイズ正解で 0 → 1（芽）。再出題を使い切っても正解できなかった場合も芽にする
- 「もう知ってる」: stage 4・+2週間 扱い
- 復習上限（60/日）: 期限超過の古い順に上限まで。期限到来数が上限を超えている日は新規語を出さない
- 日付は `Calendar.current` の `startOfDay(for:)` / `date(byAdding:)` で扱う（DST・タイムゾーン対応）

### 出題形式

ステージ連動（app-concept §4 のとおり）:

- 芽(1〜2): 英→日 4択 / つぼみ(3): 例文穴埋め 4択 / つぼみ(4): 日→英 4択 / 開花・維持(5〜): リスニング 4択
- 新規学習の直後クイズは英→日 4択
- 誤答肢は同レベル・同品詞から 3 語ランダム（不足時は同レベル→全体にフォールバック。意味文字列の重複は除外）
- 穴埋めは例文中の該当語を大小文字無視で空欄化。見つからない場合は英→日にフォールバック

### セッションフロー

ホームの「今日の学習」→ `復習 → 新規学習（5 語ミニバッチで提示 → 直後クイズ）→ 再出題 → 締め（サマリー）`。
回答ごとに即保存し、中断してもやり直し不要。ホームのボタンは 1 つに統合する。

### 画面構成

`TabView`（ホーム / 単語帳 / 統計 / 設定）+ セッションはフルスクリーンモーダル。

- `OnboardingView`: 初回のみ。レベル A1/A2 選択 → 保存
- `HomeView`: 庭（学習済み単語をステージ別の植物として描画、上限あり）+ ストリーク + 今日の学習ボタン
- `SessionView`: 上記フロー。回答後は正誤 + 単語カード（意味・例文・音声自動再生）
- `WordListView` / `WordDetailView`: デッキ別一覧・検索・成長状態 / 意味・例文・音声・次回復習日・回答履歴
- `StatsView`: 学習済み語数・開花数・正答率 + 日別回答数（直近 2 週間、`Chart` or 自前バー）
- `SettingsView`: レベル変更・新規語数/日・音声 ON/OFF・エクスポート/インポート
  - エクスポート/インポートは JSON を `ShareLink` / `fileImporter` で入出力（置き換え方式）

## Phase 分割

- **Phase 1: プロジェクト基盤** — `ios/project.yml` 作成、XcodeGen でプロジェクト生成、単語 JSON を
  `data/decks/` へ移動してバンドル同梱・デコード、SwiftData スキーマ、設定ストア、TTS ラッパー、
  ルート `TabView` 骨格、ビルド/テストのコマンド確認、Web 資産の削除
- **Phase 2: コアロジック移植** — 日付ユーティリティ・SRS・クイズ生成・セッション構築 + Swift Testing の単体テスト
- **Phase 3: オンボーディング + ホーム** — レベル選択、庭ビジュアル、ストリーク
- **Phase 4: 学習/復習セッション** — 提示カード、4 形式クイズ、再出題、締め画面
- **Phase 5: 単語帳一覧・単語詳細**
- **Phase 6: 統計・設定** — エクスポート/インポート
- **Phase 7: 仕上げ** — アプリアイコン、実機確認、Dynamic Type / VoiceOver、SwiftLint 通過

## 影響範囲

- `ios/` 以下の新規追加が中心
- `src/` は大半を削除し、データ検証テスト（`src/data/decks.test.ts` / `types.ts` / `src/lib/inflect.ts`）のみ残す
- 単語 JSON の移動に伴い `scripts/apply-review.py` の `DECK_DIR` と `decks.test.ts` の読み込みパスを更新
- `package.json` をデータ検証用にスリム化、`.gitignore` に Xcode 生成物を追加
- `README.md` / `docs/specs/app-concept.md`（§7 技術方針・§8 決定事項）を iOS ネイティブ前提に更新
- **単語データ（JSON）の中身は変更しない**

## テスト方針

- Swift Testing で純ロジックを単体テスト: SRS 遷移・間隔、クイズ生成（誤答肢・穴埋めフォールバック）、
  セッションキュー構築（復習上限・新規抑制）、ストリーク計算、日付ユーティリティ
- SwiftData はインメモリ (`ModelConfiguration(isStoredInMemoryOnly: true)`) でエクスポート/インポートの
  ラウンドトリップをテスト
- 単語データの内容検証は既存 Vitest（`npm test`）を維持
- 各 Phase 完了時に `xcodebuild -scheme VocabBlossom -destination 'platform=iOS Simulator,name=iPhone 17' build test` の通過を確認
