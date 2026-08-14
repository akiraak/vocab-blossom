# 技術スタックセットアップ プラン

## 目的・背景

[app-concept](../specs/app-concept.md) §7 の技術方針に従い、MVP 実装を始められる開発基盤を用意する。

- Vite + React + TypeScript + Tailwind CSS のレスポンシブ Web アプリ（PWA）
- ローカルファースト（IndexedDB は MVP 実装フェーズで導入。本タスクでは雛形まで）

## 対応方針

プロジェクト直下に Vite アプリを構築する（`src/`、`index.html`、`package.json` などをルートに配置。`docs/` や `vibeboard/` とは共存させる）。

- Step 1: Vite + React + TypeScript の雛形作成（既存の README.md / .gitignore / LICENSE は保持し、.gitignore には追記）
- Step 2: Tailwind CSS v4 の導入（`@tailwindcss/vite` プラグイン）
- Step 3: PWA の導入（`vite-plugin-pwa`。マニフェスト最小構成、アイコンはプレースホルダ）
- Step 4: Vitest によるテスト基盤の導入（サンプルテスト 1 件）
- Step 5: `npm run build` と `npm test` が通ることを確認

アプリ本体はプレースホルダのホーム画面（アプリ名表示のみ）とし、機能実装は MVP 実装タスクで行う。

## 影響範囲

- プロジェクト直下に新規ファイル追加（package.json、vite.config.ts、tsconfig、src/ など）
- 既存ファイルの変更は `.gitignore` への追記のみ
- `docs/`・`vibeboard/`・タスク管理ファイルには触れない

## テスト方針

- Vitest を導入し、サンプルテストが通ることを確認する
- `npm run build`（tsc + vite build）が成功することを確認する
- `npm run dev` で起動し、ページが表示されることを確認する
