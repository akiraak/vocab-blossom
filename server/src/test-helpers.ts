import { type Handle, type Logger, createApp } from './app.ts'
import type { Config } from './config.ts'
import { type DB, migrate, openDatabase } from './db.ts'

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
    ...overrides,
  }
}

export type TestApp = {
  handle: Handle
  db: DB
  logs: string[]
  errors: string[]
}

export function createTestApp(overrides: Partial<Config> = {}): TestApp {
  const db = openDatabase(':memory:')
  migrate(db)
  const logs: string[] = []
  const errors: string[] = []
  const logger: Logger = {
    info: (message) => logs.push(message),
    error: (message) => errors.push(message),
  }
  const handle = createApp({ config: testConfig(overrides), db, logger })
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
