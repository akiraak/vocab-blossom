# 仕様書をグループ中心の作りに合わせる

作成日: 2026-11-07
親プラン: [group-centric-redesign.md](group-centric-redesign.md) の Phase 5

## 目的・背景

- Phase 1〜4 で、読み上げをすべて Gemini の声にし、ホームをグループ中心にし、単語帳タブと CEFR 学習の機能を外した
- `docs/specs/app-concept.md` と `README.md` は「CEFR デッキからおまかせで毎日出す」「OS 内蔵の声」のままなので、今の作りに合わせる

## 対応方針

- `docs/specs/app-concept.md`
  - §2: ターゲットに「自分で覚えたい範囲（小テスト・教科書）がある人」を足す
  - §3（学習ループ）: グループの「学習する」・今日の復習・ドリル・穴埋め・読み上げを軸に書き直す。既知語の一括登録を消し、上限は固定値（新しい単語 10 語・復習 60 語）にする
  - §4（出題形式・音声）: 音声を Gemini の TTS（Chobi / Naruko）、取れないときは内蔵の声、と書き直す
  - §5（収録コンテンツ）: 同梱語は「単語を追加」の検索・誤答肢に使う。学習レベルの設定を消す
  - §6（画面構成）: タブ「ホーム / 統計 / 設定」、ホーム（今日の復習・グループ・庭）、グループ詳細、マイ単語（設定から）、新しいオンボーディング・設定
  - §7（技術方針）: 音声を Gemini TTS（サーバー経由）＋内蔵の声に。グループ・マイ単語のサーバー同期があることも書く
  - §8: 1 日の新規語数の決定は、2026-11-07 にグループ中心へ変えたことを追記して残す（決定の履歴なので消さない）
  - §9: MVP のまとめは当時のものとして残し、今の機能を「2026-11-07 時点の機能」として足す
- `README.md`: 技術スタックの音声（AVSpeechSynthesizer）・ディレクトリの `SpeechService`・`WordList` の説明を直す

## 影響範囲

- ドキュメントだけ（コードは変えない）

## テスト方針

- コードを変えないので、テスト・SwiftLint は不要
- 書いた内容が今のコード（`RootView`・`HomeView`・`SettingsView`・`OnboardingView`・`StudyLimits`・`GeminiReadAloudSpeaker`）と合っているかを読み比べる

## 結果（2026-11-07）

- `docs/specs/app-concept.md` の §2・§3（学習ループ・上限）・§4（音声）・§5・§6（画面構成）・§7・§8・§9 を、グループ中心の作りと Gemini の読み上げに合わせて直した。やめたこと（おまかせの新規語・学習レベル・既知語の一括登録・単語帳タブ）は、決定の履歴として改定の注記を残した
- `README.md` の冒頭・技術スタック（音声）・ディレクトリの説明を直した（DebugSeed の説明は Phase 3・4 で直した）
- 書いた内容を `RootView`・`HomeView`・`GroupDetailView`・`SettingsView`・`OnboardingView`・`StudyLimits`・`GeminiReadAloudSpeaker`（学習中の待ちは 3 秒まで）と読み比べた
