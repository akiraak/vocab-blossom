import { defineConfig } from 'vitest/config'

// アプリ本体は iOS ネイティブ（ios/）。Node 側でテストするのは
// 単語データ（data/decks/*.json）の内容検証（src/）と管理画面のサーバー（server/src/）。
export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
    include: ['src/**/*.test.ts', 'server/src/**/*.test.ts'],
  },
})
