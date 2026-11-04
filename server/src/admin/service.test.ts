import { beforeEach, describe, expect, it } from 'vitest'
import { type DB, migrate, openDatabase } from '../db.ts'
import { SyncStore } from '../sync/store.ts'
import { testBundled } from '../test-helpers.ts'
import { AdminInputError, AdminNotFoundError, AdminService, DEFAULT_GROUP_NAME, type WordDraft } from './service.ts'

const draft = (overrides: Partial<WordDraft> = {}): WordDraft => ({
  word: 'homeroom',
  meaning: 'ホームルーム',
  pos: 'noun',
  example: '',
  exampleJa: '',
  extraSenses: [],
  ...overrides,
})

const sense = (meaning: string, pos = 'noun', example = '') => ({ meaning, pos, example, exampleJa: '' })

let db: DB
let store: SyncStore
let service: AdminService
let clock: number

beforeEach(() => {
  db = openDatabase(':memory:')
  migrate(db)
  store = new SyncStore(db)
  clock = 1_000
  service = new AdminService({ db, store, bundled: testBundled(), now: () => clock })
})

describe('グループ', () => {
  it('作る（UUID は小文字・空の名前は「新しいグループ」）', () => {
    const group = service.createGroup('  ')
    expect(group.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(store.getGroup(group.id)).toEqual({
      id: group.id,
      name: DEFAULT_GROUP_NAME,
      wordIds: [],
      createdAt: 1_000,
      updatedAt: 1_000,
    })
  })

  it('名前を変える。同じ名前なら rev も日時も進めない', () => {
    const group = service.createGroup('旅行')
    clock = 2_000
    service.renameGroup(group.id, ' 旅行で使う ')
    expect(store.getGroup(group.id)).toMatchObject({ name: '旅行で使う', updatedAt: 2_000 })

    const rev = store.currentRev()
    clock = 3_000
    service.renameGroup(group.id, '旅行で使う')
    expect(store.currentRev()).toBe(rev)
    expect(store.getGroup(group.id)?.updatedAt).toBe(2_000)
  })

  it('端末の時計が進んでいても、管理画面の変更は今の updatedAt より新しくする', () => {
    const group = service.createGroup('旅行')
    store.applyGroup({ ...store.getGroup(group.id)!, updatedAt: 50_000 })
    clock = 2_000
    service.renameGroup(group.id, '出張')
    expect(store.getGroup(group.id)).toMatchObject({ name: '出張', updatedAt: 50_001 })
  })

  it('削除すると削除記録が残り、同期で届く', () => {
    const group = service.createGroup('旅行')
    const cursor = store.currentRev()
    clock = 2_000
    service.deleteGroup(group.id)
    expect(store.getGroup(group.id)).toBeNull()
    const res = store.sync({ cursor, groups: [], customWords: [], deletions: [] })
    expect(res.deletions).toEqual([{ kind: 'group', id: group.id, deletedAt: 2_000 }])
  })

  it('大文字の ID でも引ける・無い ID は AdminNotFoundError', () => {
    const group = service.createGroup('旅行')
    expect(service.getGroup(group.id.toUpperCase()).id).toBe(group.id)
    expect(() => service.getGroup('00000000-0000-0000-0000-000000000000')).toThrow(AdminNotFoundError)
    expect(() => service.renameGroup('nope', 'x')).toThrow(AdminNotFoundError)
  })

  it('長すぎる名前は AdminInputError', () => {
    expect(() => service.createGroup('あ'.repeat(201))).toThrow(AdminInputError)
  })
})

describe('グループの中の語', () => {
  it('末尾に足す。入っている語は飛ばし、何も変わらなければ rev を進めない', () => {
    const group = service.createGroup('旅行')
    service.addWords(group.id, ['a1-0001', 'a1-0002'])
    service.addWords(group.id, ['a1-0002', 'a1-0003'])
    expect(store.getGroup(group.id)?.wordIds).toEqual(['a1-0001', 'a1-0002', 'a1-0003'])

    const rev = store.currentRev()
    service.addWords(group.id, ['a1-0001'])
    expect(store.currentRev()).toBe(rev)
  })

  it('存在しない語は追加できない', () => {
    const group = service.createGroup('旅行')
    expect(() => service.addWords(group.id, ['zz-9999'])).toThrow(AdminInputError)
    expect(() => service.addWords(group.id, ['custom-nope'])).toThrow(AdminInputError)
    expect(store.getGroup(group.id)?.wordIds).toEqual([])
  })

  it('外す・上へ・下へ（端では何もしない）', () => {
    const group = service.createGroup('旅行')
    service.addWords(group.id, ['a1-0001', 'a1-0002', 'a1-0003'])

    service.moveWord(group.id, 'a1-0003', 'up')
    expect(store.getGroup(group.id)?.wordIds).toEqual(['a1-0001', 'a1-0003', 'a1-0002'])
    service.moveWord(group.id, 'a1-0001', 'down')
    expect(store.getGroup(group.id)?.wordIds).toEqual(['a1-0003', 'a1-0001', 'a1-0002'])

    const rev = store.currentRev()
    service.moveWord(group.id, 'a1-0003', 'up')
    service.moveWord(group.id, 'a1-0002', 'down')
    service.moveWord(group.id, 'a1-9999', 'down')
    expect(store.currentRev()).toBe(rev)

    service.removeWord(group.id, 'a1-0001')
    expect(store.getGroup(group.id)?.wordIds).toEqual(['a1-0003', 'a1-0002'])
  })

  it('解決できない ID は unknown として出す', () => {
    const group = service.createGroup('旅行')
    service.addWords(group.id, ['a1-0001'])
    store.applyGroup({ ...store.getGroup(group.id)!, wordIds: ['a1-0001', 'custom-later'], updatedAt: 9_000 })
    const custom = service.createCustomWord(draft(), group.id)
    expect(service.entries(service.getGroup(group.id))).toEqual([
      { kind: 'bundled', id: 'a1-0001', word: 'a.m.', meaning: '午前', pos: 'adverb', level: 'A1' },
      { kind: 'unknown', id: 'custom-later' },
      { kind: 'custom', id: custom.wordId, word: 'homeroom', meaning: 'ホームルーム', pos: 'noun', extraSenses: [] },
    ])
  })
})

describe('自作語', () => {
  it('作ってグループの末尾に入れる（1 トランザクション）', () => {
    const group = service.createGroup('学校')
    service.addWords(group.id, ['a1-0001'])
    clock = 2_000
    const word = service.createCustomWord(draft({ word: ' homeroom ', example: 'We have homeroom.' }), group.id)
    expect(word.wordId).toMatch(/^custom-[0-9a-f-]{36}$/)
    expect(store.getCustomWord(word.wordId)).toEqual({
      wordId: word.wordId,
      word: 'homeroom',
      meaning: 'ホームルーム',
      pos: 'noun',
      example: 'We have homeroom.',
      exampleJa: '',
      extraSenses: [],
      createdAt: 2_000,
      updatedAt: 2_000,
    })
    expect(store.getGroup(group.id)?.wordIds).toEqual(['a1-0001', word.wordId])
  })

  it('2 つ目以降の意味を作り・直し・消せる（欄がすべて空の意味は無視し、前後の空白は落とす）', () => {
    const word = service.createCustomWord(
      draft({
        word: 'commute',
        meaning: '通勤する',
        pos: 'verb',
        extraSenses: [sense(' 通勤 ', 'noun', ' My commute is long. '), sense('', 'adjective')],
      }),
    )
    expect(store.getCustomWord(word.wordId)?.extraSenses).toEqual([
      { pos: 'noun', meaning: '通勤', example: 'My commute is long.', exampleJa: '' },
    ])

    clock = 5_000
    service.updateCustomWord(
      word.wordId,
      draft({ word: 'commute', meaning: '通勤する', pos: 'verb', extraSenses: [sense('通学', 'noun')] }),
    )
    expect(store.getCustomWord(word.wordId)?.extraSenses).toEqual([
      { pos: 'noun', meaning: '通学', example: '', exampleJa: '' },
    ])

    clock = 6_000
    service.updateCustomWord(word.wordId, draft({ word: 'commute', meaning: '通勤する', pos: 'verb' }))
    expect(store.getCustomWord(word.wordId)?.extraSenses).toEqual([])
  })

  it('2 つ目以降の意味の検証（例文だけで意味が無い・品詞が一覧に無い・数の上限）', () => {
    expect(() => service.createCustomWord(draft({ extraSenses: [sense('', 'noun', 'An example.')] }))).toThrow(
      '意味 2 の意味を入れてください',
    )
    expect(() => service.createCustomWord(draft({ extraSenses: [sense('x', 'noun'), sense('y', 'nope')] }))).toThrow(
      '意味 3 の品詞を選んでください',
    )
    const many = Array.from({ length: 11 }, (_, i) => sense(`意味${i}`))
    expect(() => service.createCustomWord(draft({ extraSenses: many }))).toThrow('意味は 11 個までです')
    expect(store.listCustomWords()).toEqual([])
  })

  it('グループが無ければ自作語も作らない', () => {
    expect(() => service.createCustomWord(draft(), '00000000-0000-0000-0000-000000000000')).toThrow(
      AdminNotFoundError,
    )
    expect(store.listCustomWords()).toEqual([])
  })

  it('入力の検証（英語・意味は必須、品詞は一覧のどれか、長さの上限）', () => {
    expect(() => service.createCustomWord(draft({ word: ' ' }))).toThrow('英語を入れてください')
    expect(() => service.createCustomWord(draft({ meaning: '' }))).toThrow('意味を入れてください')
    expect(() => service.createCustomWord(draft({ pos: 'verbb' }))).toThrow('品詞を選んでください')
    expect(() => service.createCustomWord(draft({ example: 'a'.repeat(1001) }))).toThrow(AdminInputError)
    expect(store.listCustomWords()).toEqual([])
  })

  it('編集する（作った日時は変えない）', () => {
    const word = service.createCustomWord(draft())
    clock = 2_000
    service.updateCustomWord(word.wordId, draft({ meaning: '朝の会', pos: 'phrase' }))
    expect(store.getCustomWord(word.wordId)).toMatchObject({
      meaning: '朝の会',
      pos: 'phrase',
      createdAt: 1_000,
      updatedAt: 2_000,
    })
    expect(() => service.updateCustomWord('custom-nope', draft())).toThrow(AdminNotFoundError)
  })

  it('削除するとすべてのグループから外れ、同期で削除記録とグループが届く', () => {
    const a = service.createGroup('A')
    const b = service.createGroup('B')
    const word = service.createCustomWord(draft(), a.id)
    service.addWords(b.id, ['a1-0001', word.wordId])
    const cursor = store.currentRev()

    clock = 5_000
    service.deleteCustomWord(word.wordId)
    expect(store.getCustomWord(word.wordId)).toBeNull()
    expect(store.getGroup(a.id)?.wordIds).toEqual([])
    expect(store.getGroup(b.id)?.wordIds).toEqual(['a1-0001'])

    const res = store.sync({ cursor, groups: [], customWords: [], deletions: [] })
    expect(res.deletions).toEqual([{ kind: 'customWord', id: word.wordId, deletedAt: 5_000 }])
    expect(res.groups.map((g) => g.id).sort()).toEqual([a.id, b.id].sort())
  })

  it('自作語ごとに入っているグループ', () => {
    const a = service.createGroup('A')
    const b = service.createGroup('B')
    const word = service.createCustomWord(draft(), a.id)
    service.addWords(b.id, [word.wordId])
    const lonely = service.createCustomWord(draft({ word: 'lunchbox' }))
    const map = service.groupsByCustomWord()
    expect(map.get(word.wordId)?.map((g) => g.name).sort()).toEqual(['A', 'B'])
    expect(map.get(lonely.wordId)).toBeUndefined()
  })
})

describe('管理画面の変更は端末の cursor 以降として届く', () => {
  it('グループ・自作語の作成と変更', () => {
    const cursor = store.currentRev()
    const group = service.createGroup('旅行')
    const word = service.createCustomWord(draft(), group.id)
    const res = store.sync({ cursor, groups: [], customWords: [], deletions: [] })
    expect(res.groups).toEqual([store.getGroup(group.id)])
    expect(res.customWords).toEqual([store.getCustomWord(word.wordId)])
    expect(res.cursor).toBe(store.currentRev())
  })
})
