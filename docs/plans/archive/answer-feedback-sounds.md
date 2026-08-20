# 問題回答時の正解・不正解にわかりやすい音を入れる

## 目的・背景

クイズに回答したときのフィードバックが画面表示（色・アイコン）だけで、正誤が耳に残らない。
クイズ番組式の「ピンポン / ブッブー」を鳴らして、画面を凝視していなくても正誤が即座に分かるようにする。

## 対応方針

### 1. 効果音はアセットを持たず、コードで波形を合成する（新規: `Core/SoundEffect.swift`）

- 音声ファイルを同梱すると生成パイプラインとアセット管理が増えるので、短いチャイム / ブザーを
  起動時に PCM 合成し、WAV に包んで `AVAudioPlayer` で鳴らす
- `SoundEffect`（enum・純粋関数）: 波形の定義と合成。テストできる形にする
  - `.correct`: 4 度上がる 2 音のチャイム（G5 → C6、ピンポン）
  - `.incorrect`: 低いブザー 2 連（ブッブー）。iPhone のスピーカーは低域が出ないので、
    基音 196Hz に奇数倍音を重ねて「ブー」の音色を作る
  - クリックノイズが出ないよう、鳴り始めと終わりは無音に近づける（アタック / リリース）
- `SoundEffectService`: `AVAudioPlayer` を 2 つ用意して鳴らすだけの薄い層
- システムサウンド（`AudioServicesPlaySystemSound`）はマナーモードで鳴らないので使わない。
  読み上げと同じく `.playback` セッションで鳴らす

### 2. 音声セッションの準備を読み上げと共有する（新規: `Core/LearningAudioSession.swift`）

`SpeechService.prepareSession`（カテゴリ設定 + 有効化、失敗したら次回やり直す）を切り出して
効果音と共有する。カテゴリを二重管理して設定が食い違うのを避ける。

### 3. 鳴らすタイミング（`SessionView`）

- 回答した瞬間（`selectedIndex` が立ったとき）に正誤の効果音を鳴らす
- 既存の「回答後に単語と例文を読み上げる」は、効果音と重ならないよう 0.5 秒待ってから始める。
  `onChange` を `.task(id: runner.selectedIndex)` に置き換え、読み上げ前に「次へ」で進んだら
  読み上げを取りやめる（次のカードの読み上げと衝突させない）

### 4. 設定（`AppSettings` / `SettingsView`）

- `effectSoundEnabled`（既定 ON）を追加。「自動で読み上げる」とは独立に切れるようにする
  （読み上げは要らないが正誤音は欲しい、という使い方があるため）
- バックアップ形式（`BackupArchive.Settings`）には**入れない**。フィールドを足すと旧ファイルの
  デコードが壊れる（バージョン繰り上げが要る）割に、端末ごとの好みなので復元する価値が薄い

## 影響範囲

| 箇所 | 影響 |
|---|---|
| `Core/SoundEffect.swift` | 新規（波形合成 + 再生） |
| `Core/LearningAudioSession.swift` | 新規（セッション準備の共有） |
| `Core/SpeechService.swift` | `prepareSession` を共有化 |
| `Core/AppSettings.swift` | `effectSoundEnabled` を追加 |
| `Features/Settings/SettingsView.swift` | 「正解・不正解の音」トグルを追加 |
| `Features/Session/SessionView.swift` | 回答時に効果音 → 少し置いて読み上げ |
| バックアップ形式 | 変更なし |

## テスト方針

- `SoundEffectTests`（新規）
  - 波形が想定の長さで、クリップしない（振幅 ≤ 1.0）・小さすぎない
  - 鳴り始めと終わりが無音に近い（クリックノイズを出さない）
  - 正解と不正解で違う波形になる
  - 合成した WAV を `AVAudioPlayer` が読み込める（長さも想定どおり）
  - 連続再生してもクラッシュしない
- `AppSettingsTests`: `effectSoundEnabled` の既定値と永続化を追加
- `SpeechServiceTests`（既存）でセッション共有化のデグレを検知する
- `xcodebuild test` と `swiftlint`（警告 0）を通す
