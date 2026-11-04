import { beforeEach, describe, expect, it } from 'vitest'
import { MIGRATIONS, migrate, openDatabase } from '../db.ts'
import { SyncStore } from './store.ts'
import type { CustomWord, Group, SyncRequest } from './types.ts'

const G1 = '00000000-0000-4000-8000-000000000001'
const G2 = '00000000-0000-4000-8000-000000000002'

const group = (overrides: Partial<Group> = {}): Group => ({
  id: G1,
  name: '旅行',
  wordIds: ['a1-apple'],
  createdAt: 100,
  updatedAt: 100,
  ...overrides,
})

const word = (overrides: Partial<CustomWord> = {}): CustomWord => ({
  wordId: 'custom-x',
  word: 'boarding pass',
  meaning: '搭乗券',
  pos: 'phrase',
  example: '',
  exampleJa: '',
  extraSenses: [],
  createdAt: 100,
  updatedAt: 100,
  ...overrides,
})

const request = (overrides: Partial<SyncRequest> = {}): SyncRequest => ({
  cursor: 0,
  groups: [],
  customWords: [],
  deletions: [],
  ...overrides,
})

let store: SyncStore

beforeEach(() => {
  const db = openDatabase(':memory:')
  migrate(db)
  store = new SyncStore(db)
})

describe('applyGroup / applyCustomWord', () => {
  it('新しいレコードを保存し rev を振る', () => {
    expect(store.currentRev()).toBe(0)
    expect(store.applyGroup(group())).toBe('applied')
    expect(store.applyCustomWord(word())).toBe('applied')
    expect(store.currentRev()).toBe(2)
    expect(store.getGroup(G1)).toEqual(group())
    expect(store.getCustomWord('custom-x')).toEqual(word())
  })

  it('updatedAt が新しければ置き換え、古い・同じなら捨てる', () => {
    store.applyGroup(group({ updatedAt: 200 }))
    expect(store.applyGroup(group({ name: '古い', updatedAt: 150 }))).toBe('ignored')
    expect(store.applyGroup(group({ name: '同時', updatedAt: 200 }))).toBe('ignored')
    expect(store.getGroup(G1)?.name).toBe('旅行')
    expect(store.applyGroup(group({ name: '新しい', wordIds: ['b', 'a'], updatedAt: 300 }))).toBe('applied')
    expect(store.getGroup(G1)).toMatchObject({ name: '新しい', wordIds: ['b', 'a'] })

    store.applyCustomWord(word({ updatedAt: 200 }))
    expect(store.applyCustomWord(word({ meaning: '古い', updatedAt: 199 }))).toBe('ignored')
    expect(store.applyCustomWord(word({ meaning: '新しい', updatedAt: 201 }))).toBe('applied')
    expect(store.getCustomWord('custom-x')?.meaning).toBe('新しい')
  })

  it('意味を複数持てるようになる前の DB も、移行すると 2 つ目以降の意味が空の語として読める', () => {
    const db = openDatabase(':memory:')
    migrate(db, MIGRATIONS.slice(0, 1))
    db.prepare(
      `INSERT INTO custom_words (word_id, word, meaning, pos, example, example_ja, created_at, updated_at, rev)
       VALUES ('custom-old', 'homeroom', 'ホームルーム', 'noun', '', '', 1, 1, 1)`,
    ).run()
    migrate(db)
    expect(new SyncStore(db).getCustomWord('custom-old')?.extraSenses).toEqual([])
  })

  it('自作語の 2 つ目以降の意味を保存して読み出す', () => {
    const senses = [
      { pos: 'noun' as const, meaning: '通勤', example: 'My commute is long.', exampleJa: '通勤が長い。' },
      { pos: 'adjective' as const, meaning: '（テスト）', example: '', exampleJa: '' },
    ]
    store.applyCustomWord(word({ word: 'commute', pos: 'verb', meaning: '通勤する', extraSenses: senses }))
    expect(store.getCustomWord('custom-x')?.extraSenses).toEqual(senses)

    store.applyCustomWord(word({ word: 'commute', pos: 'verb', meaning: '通勤する', updatedAt: 200 }))
    expect(store.getCustomWord('custom-x')?.extraSenses).toEqual([])
  })

  it('同じものを 2 回当てても rev は進まない', () => {
    store.applyGroup(group())
    const rev = store.currentRev()
    expect(store.applyGroup(group())).toBe('ignored')
    expect(store.currentRev()).toBe(rev)
  })

  it('グループを受け取ったとき、削除された自作語の ID は抜く', () => {
    store.applyDeletion({ kind: 'customWord', id: 'custom-gone', deletedAt: 50 })
    store.applyGroup(group({ wordIds: ['a1-apple', 'custom-gone', 'custom-unknown'] }))
    expect(store.getGroup(G1)?.wordIds).toEqual(['a1-apple', 'custom-unknown'])
  })
})

describe('applyDeletion', () => {
  it('グループを消して削除記録を残す。中の自作語は残る', () => {
    store.applyCustomWord(word())
    store.applyGroup(group({ wordIds: ['custom-x'] }))
    expect(store.applyDeletion({ kind: 'group', id: G1, deletedAt: 200 })).toBe('applied')
    expect(store.getGroup(G1)).toBeNull()
    expect(store.getDeletion('group', G1)).toEqual({ kind: 'group', id: G1, deletedAt: 200 })
    expect(store.getCustomWord('custom-x')).not.toBeNull()
  })

  it('サーバーのレコードの方が新しければ削除を捨てる。同じ時刻なら削除が勝つ', () => {
    store.applyGroup(group({ updatedAt: 300 }))
    expect(store.applyDeletion({ kind: 'group', id: G1, deletedAt: 299 })).toBe('ignored')
    expect(store.getGroup(G1)).not.toBeNull()
    expect(store.applyDeletion({ kind: 'group', id: G1, deletedAt: 300 })).toBe('applied')
    expect(store.getGroup(G1)).toBeNull()
  })

  it('削除より古い更新は捨て、新しい更新なら復活して削除記録を消す', () => {
    store.applyDeletion({ kind: 'group', id: G1, deletedAt: 200 })
    expect(store.applyGroup(group({ updatedAt: 200 }))).toBe('ignored')
    expect(store.getGroup(G1)).toBeNull()
    expect(store.applyGroup(group({ updatedAt: 201 }))).toBe('applied')
    expect(store.getGroup(G1)).not.toBeNull()
    expect(store.getDeletion('group', G1)).toBeNull()

    store.applyDeletion({ kind: 'customWord', id: 'custom-x', deletedAt: 200 })
    expect(store.applyCustomWord(word({ updatedAt: 150 }))).toBe('ignored')
    expect(store.applyCustomWord(word({ updatedAt: 250 }))).toBe('applied')
    expect(store.getDeletion('customWord', 'custom-x')).toBeNull()
  })

  it('同じ削除を 2 回当てても rev は進まない', () => {
    store.applyDeletion({ kind: 'group', id: G1, deletedAt: 200 })
    const rev = store.currentRev()
    expect(store.applyDeletion({ kind: 'group', id: G1, deletedAt: 200 })).toBe('ignored')
    expect(store.applyDeletion({ kind: 'group', id: G1, deletedAt: 100 })).toBe('ignored')
    expect(store.currentRev()).toBe(rev)
  })

  it('自作語を消すと、すべてのグループから外れ、グループの updatedAt が削除の時刻まで進む', () => {
    store.applyCustomWord(word())
    store.applyGroup(group({ id: G1, wordIds: ['a1-apple', 'custom-x', 'a1-cat'], updatedAt: 100 }))
    store.applyGroup(group({ id: G2, wordIds: ['custom-x'], updatedAt: 500 }))
    store.applyGroup(group({ id: '00000000-0000-4000-8000-000000000003', wordIds: ['a1-dog'] }))
    const before = store.currentRev()

    expect(store.applyDeletion({ kind: 'customWord', id: 'custom-x', deletedAt: 300 })).toBe('applied')
    expect(store.getCustomWord('custom-x')).toBeNull()
    expect(store.getGroup(G1)).toMatchObject({ wordIds: ['a1-apple', 'a1-cat'], updatedAt: 300 })
    // もともと新しいグループの updatedAt は戻さない
    expect(store.getGroup(G2)).toMatchObject({ wordIds: [], updatedAt: 500 })
    // 削除記録 + 外したグループ 2 つ
    expect(store.currentRev()).toBe(before + 3)
  })
})

describe('sync', () => {
  it('端末の変更を保存し、新しい cursor を返す', () => {
    const res = store.sync(request({ groups: [group()], customWords: [word()] }))
    expect(res.cursor).toBe(2)
    expect(res.reset).toBe(false)
    expect(store.getGroup(G1)).toEqual(group())
    expect(store.getCustomWord('custom-x')).toEqual(word())
    // 送ったものはサーバーの今の状態として返る
    expect(res.groups).toEqual([group()])
    expect(res.customWords).toEqual([word()])
  })

  it('管理画面などサーバーでの変更が cursor より後として返る', () => {
    const first = store.sync(request())
    expect(first).toEqual({ cursor: 0, reset: false, groups: [], customWords: [], deletions: [] })

    store.applyGroup(group({ name: '管理画面で作った' }))
    store.applyDeletion({ kind: 'customWord', id: 'custom-y', deletedAt: 100 })
    const second = store.sync(request({ cursor: first.cursor }))
    expect(second.cursor).toBe(2)
    expect(second.groups.map((g) => g.name)).toEqual(['管理画面で作った'])
    expect(second.deletions).toEqual([{ kind: 'customWord', id: 'custom-y', deletedAt: 100 }])

    // 受け取り済みの分は返さない
    expect(store.sync(request({ cursor: second.cursor }))).toMatchObject({
      cursor: 2,
      groups: [],
      customWords: [],
      deletions: [],
    })
  })

  it('ぶつかったら新しい方。採用しなかった変更にはサーバーの値を返す', () => {
    store.applyGroup(group({ name: 'サーバー', updatedAt: 300 }))
    const cursor = store.currentRev()
    const res = store.sync(request({ cursor, groups: [group({ name: '端末（古い）', updatedAt: 200 })] }))
    expect(res.cursor).toBe(cursor)
    expect(res.groups).toEqual([group({ name: 'サーバー', updatedAt: 300 })])

    const newer = store.sync(request({ cursor, groups: [group({ name: '端末（新しい）', updatedAt: 400 })] }))
    expect(newer.groups.map((g) => g.name)).toEqual(['端末（新しい）'])
    expect(store.getGroup(G1)?.name).toBe('端末（新しい）')
  })

  it('端末の更新がサーバーの削除より古ければ、削除記録を返す', () => {
    store.applyDeletion({ kind: 'group', id: G1, deletedAt: 300 })
    const cursor = store.currentRev()
    const res = store.sync(request({ cursor, groups: [group({ updatedAt: 200 })] }))
    expect(res.groups).toEqual([])
    expect(res.deletions).toEqual([{ kind: 'group', id: G1, deletedAt: 300 }])
  })

  it('端末の削除記録が届き、自作語の削除でグループからも外れる', () => {
    store.sync(request({ groups: [group({ wordIds: ['custom-x', 'a1-apple'] })], customWords: [word()] }))
    const cursor = store.currentRev()
    const res = store.sync(
      request({ cursor, deletions: [{ kind: 'customWord', id: 'custom-x', deletedAt: 200 }] }),
    )
    expect(store.getCustomWord('custom-x')).toBeNull()
    expect(res.deletions).toEqual([{ kind: 'customWord', id: 'custom-x', deletedAt: 200 }])
    expect(res.groups).toEqual([group({ wordIds: ['a1-apple'], updatedAt: 200 })])
  })

  it('同じ内容を 2 回送っても壊れない', () => {
    const body = request({
      groups: [group({ wordIds: ['custom-x'] })],
      customWords: [word()],
      deletions: [{ kind: 'group', id: G2, deletedAt: 100 }],
    })
    const first = store.sync(body)
    const second = store.sync({ ...body, cursor: first.cursor })
    expect(second.cursor).toBe(first.cursor)
    expect(second.groups).toEqual(first.groups)
    expect(second.customWords).toEqual(first.customWords)
    expect(second.deletions).toEqual(first.deletions)
    expect(store.listGroups()).toHaveLength(1)
  })

  it('同じ同期の中で、作って消した自作語はグループに残らない', () => {
    store.sync(
      request({
        customWords: [word({ updatedAt: 100 })],
        groups: [group({ wordIds: ['custom-x', 'a1-apple'], updatedAt: 100 })],
        deletions: [{ kind: 'customWord', id: 'custom-x', deletedAt: 200 }],
      }),
    )
    expect(store.getCustomWord('custom-x')).toBeNull()
    expect(store.getGroup(G1)?.wordIds).toEqual(['a1-apple'])
  })

  it('端末の cursor の方が進んでいたら（DB を作り直した）reset を付けて全件を返す', () => {
    store.applyGroup(group())
    const res = store.sync(request({ cursor: 99 }))
    expect(res.reset).toBe(true)
    expect(res.cursor).toBe(1)
    expect(res.groups).toEqual([group()])
  })

  it('返すレコードは rev の順', () => {
    store.applyGroup(group({ id: G2, name: '先' }))
    store.applyGroup(group({ id: G1, name: '後' }))
    const res = store.sync(request())
    expect(res.groups.map((g) => g.name)).toEqual(['先', '後'])
  })
})
