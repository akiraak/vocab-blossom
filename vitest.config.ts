import { defineConfig } from 'vitest/config'

// アプリ本体は iOS ネイティブ（ios/）へ移行済み。
// Node 側に残しているのは単語データ（data/decks/*.json）の内容検証だけ。
export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
  },
})
