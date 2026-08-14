# vocab-blossom

覚えた単語が花になって庭が育つ、英語初学者（CEFR A1〜A2）向けの単語学習 Web アプリ（PWA）。

コンセプトの詳細は [docs/specs/app-concept.md](docs/specs/app-concept.md) を参照。

## 開発

```bash
npm install
npm run dev      # 開発サーバー (http://localhost:5173)
npm run build    # 型チェック + プロダクションビルド
npm test         # テスト実行 (Vitest)
```

## 技術スタック

- Vite + React + TypeScript
- Tailwind CSS v4
- vite-plugin-pwa（PWA 対応）
- Vitest + Testing Library
