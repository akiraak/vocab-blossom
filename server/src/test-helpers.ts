import { type Handle, type Logger, createApp } from './app.ts'
import type { Config } from './config.ts'
import { type DB, migrate, openDatabase } from './db.ts'
import { BundledWords } from './words/bundled.ts'
import type { WordAssistant } from './ai/word-assist.ts'
import type { PassageWriter } from './ai/passages.ts'
import type { SpeechSynthesizer } from './ai/speech.ts'

// テスト用: サーバーを起動せずに handle(new Request(...)) で叩く

export const TEST_SECRET = 'test-secret'
export const TEST_ORIGIN = 'http://vocab.test'

export function testConfig(overrides: Partial<Config> = {}): Config {
  return {
    port: 0,
    apiSharedSecret: TEST_SECRET,
    adminEnabled: true,
    dbPath: ':memory:',
    anthropicApiKey: undefined,
    anthropicModel: undefined,
    geminiApiKey: undefined,
    geminiTtsModel: undefined,
    ...overrides,
  }
}

/** 同梱語はテスト全体で 1 回だけ読む */
let bundledCache: BundledWords | undefined
export function testBundled(): BundledWords {
  bundledCache ??= BundledWords.load()
  return bundledCache
}

export type TestApp = {
  handle: Handle
  db: DB
  logs: string[]
  errors: string[]
}

export function createTestApp(
  overrides: Partial<Config> = {},
  {
    now,
    assistant = null,
    passageWriter = null,
    speechSynthesizer = null,
  }: {
    now?: () => number
    assistant?: WordAssistant | null
    passageWriter?: PassageWriter | null
    speechSynthesizer?: SpeechSynthesizer | null
  } = {},
): TestApp {
  const db = openDatabase(':memory:')
  migrate(db)
  const logs: string[] = []
  const errors: string[] = []
  const logger: Logger = {
    info: (message) => logs.push(message),
    error: (message) => errors.push(message),
  }
  const handle = createApp({
    config: testConfig(overrides),
    db,
    logger,
    now,
    bundled: testBundled(),
    assistant,
    passageWriter,
    speechSynthesizer,
  })
  return { handle, db, logs, errors }
}

export function req(path: string, init: RequestInit = {}): Request {
  return new Request(`${TEST_ORIGIN}${path}`, init)
}

export function apiReq(path: string, init: RequestInit = {}): Request {
  const headers = new Headers(init.headers)
  headers.set('authorization', `Bearer ${TEST_SECRET}`)
  return req(path, { ...init, headers })
}

/** 管理画面のフォーム送信（自分のホストからの POST） */
/** fields は同じ名前を何度も送るときは [名前, 値] の並びで渡す */
export function adminPost(path: string, fields: Record<string, string> | [string, string][] = {}): Request {
  return req(path, {
    method: 'POST',
    headers: { origin: TEST_ORIGIN, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields).toString(),
  })
}
