import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { type Migration, migrate, openDatabase } from './db.ts'

const migrations: Migration[] = [
  { name: 'items', up: (db) => db.exec('CREATE TABLE items (id TEXT PRIMARY KEY)') },
  { name: 'items.name', up: (db) => db.exec('ALTER TABLE items ADD COLUMN name TEXT') },
]

const version = (db: ReturnType<typeof openDatabase>) => db.pragma('user_version', { simple: true })

describe('migrate', () => {
  it('未適用のものを順に当てて user_version を進める', () => {
    const db = openDatabase(':memory:')
    expect(migrate(db, migrations.slice(0, 1))).toBe(1)
    expect(version(db)).toBe(1)

    expect(migrate(db, migrations)).toBe(1)
    expect(version(db)).toBe(2)
    db.prepare('INSERT INTO items (id, name) VALUES (?, ?)').run('a', 'apple')

    // 2 回目は何もしない
    expect(migrate(db, migrations)).toBe(0)
  })

  it('途中で失敗したらそのマイグレーションは巻き戻り、版も進まない', () => {
    const db = openDatabase(':memory:')
    const broken: Migration[] = [
      migrations[0],
      {
        name: 'broken',
        up: (d) => {
          d.exec('CREATE TABLE half (id TEXT)')
          d.exec('NOT SQL')
        },
      },
    ]
    expect(() => migrate(db, broken)).toThrow()
    expect(version(db)).toBe(1)
    const tables = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all()
    expect(tables).toEqual([{ name: 'items' }])
  })

  it('DB の方が新しい版なら起動しない', () => {
    const db = openDatabase(':memory:')
    migrate(db, migrations)
    expect(() => migrate(db, migrations.slice(0, 1))).toThrow(/新しい/)
  })
})

describe('openDatabase', () => {
  let dir: string | undefined
  afterEach(() => {
    if (dir) fs.rmSync(dir, { recursive: true, force: true })
  })

  it('置き場所のディレクトリが無ければ作り、WAL で開く', () => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vocab-db-'))
    const dbPath = path.join(dir, 'nested', 'vocab.db')
    const db = openDatabase(dbPath)
    expect(db.pragma('journal_mode', { simple: true })).toBe('wal')
    expect(db.pragma('foreign_keys', { simple: true })).toBe(1)
    db.close()
    expect(fs.existsSync(dbPath)).toBe(true)
  })
})
