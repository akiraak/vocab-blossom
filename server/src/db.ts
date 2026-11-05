import fs from 'node:fs'
import path from 'node:path'
import Database from 'better-sqlite3'
import { FILL_BLANK_CHECKS_MIGRATION } from './ai/fill-blank-checks.ts'
import { PASSAGES_MIGRATION } from './ai/passages.ts'
import { EXTRA_SENSES_MIGRATION, SYNC_MIGRATION } from './sync/store.ts'

export type DB = Database.Database

/** 1 つのマイグレーション。並び順が版になる（PRAGMA user_version に適用済みの数を入れる） */
export type Migration = {
  name: string
  up: (db: DB) => void
}

// 適用済みのものは書き換えない。変更は末尾に足す
export const MIGRATIONS: Migration[] = [
  SYNC_MIGRATION,
  EXTRA_SENSES_MIGRATION,
  PASSAGES_MIGRATION,
  FILL_BLANK_CHECKS_MIGRATION,
]

export function openDatabase(dbPath: string): DB {
  if (dbPath !== ':memory:') {
    fs.mkdirSync(path.dirname(dbPath), { recursive: true })
  }
  const db = new Database(dbPath)
  db.pragma('journal_mode = WAL')
  db.pragma('foreign_keys = ON')
  db.pragma('busy_timeout = 5000')
  return db
}

/** まだ適用していないマイグレーションを順に 1 つずつトランザクションで当てる。当てた数を返す */
export function migrate(db: DB, migrations: Migration[] = MIGRATIONS): number {
  const current = db.pragma('user_version', { simple: true }) as number
  if (current > migrations.length) {
    throw new Error(
      `DB の版（${current}）がこのサーバーの知っている版（${migrations.length}）より新しい`,
    )
  }
  const pending = migrations.slice(current)
  pending.forEach((migration, i) => {
    const version = current + i + 1
    db.transaction(() => {
      migration.up(db)
      db.pragma(`user_version = ${version}`)
    })()
  })
  return pending.length
}
