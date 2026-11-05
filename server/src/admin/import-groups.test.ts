import { readFileSync } from 'node:fs'
import path from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import { type DB, migrate, openDatabase } from '../db.ts'
import { SyncStore } from '../sync/store.ts'
import { testBundled } from '../test-helpers.ts'
import { formatReports, type ImportInput, ImportInputError, importGroups, parseImportInput } from './import-groups.ts'
import { AdminService } from './service.ts'

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

const run = (input: ImportInput, dryRun = false) =>
  importGroups({ db, service, bundled: testBundled() }, input, { dryRun })

const unless = {
  word: 'unless',
  pos: 'conjunction',
  meaning: '〜しない限り（後ろに文）',
  example: 'You will be late unless you hurry.',
  exampleJa: '急がない限り、あなたは遅れますよ。',
}

const input: ImportInput = {
  groups: [
    { name: '条件', words: [{ bundled: 'a1-0452', word: 'if' }, unless] },
    { name: '時', words: [{ bundled: 'a1-0075', word: 'before' }] },
  ],
}

/** グループ名ごとの語（綴り）の並び */
function snapshot(): Record<string, string[]> {
  return Object.fromEntries(
    service.listGroups().map((group) => [
      group.name,
      service.entries(group).map((entry) => (entry.kind === 'unknown' ? entry.id : entry.word)),
    ]),
  )
}

describe('importGroups', () => {
  it('グループを作り、単語帳の語とマイ単語を並びどおりに入れる', () => {
    const reports = run(input)
    expect(snapshot()).toEqual({ 条件: ['if', 'unless'], 時: ['before'] })
    expect(reports).toEqual([
      { name: '条件', created: true, added: ['if', 'unless'], alreadyIn: [], customCreated: ['unless'], customReplaced: [] },
      { name: '時', created: true, added: ['before'], alreadyIn: [], customCreated: [], customReplaced: [] },
    ])
    const [custom] = service.listCustomWords()
    expect(custom).toMatchObject({ ...unless, extraSenses: [] })
  })

  it('2 回動かしても増えず、日時も進めない', () => {
    run(input)
    const groups = service.listGroups()
    const words = service.listCustomWords()
    clock = 9_000
    const reports = run(input)
    expect(service.listGroups()).toEqual(groups)
    expect(service.listCustomWords()).toEqual(words)
    expect(reports.map((r) => [r.created, r.added, r.alreadyIn])).toEqual([
      [false, [], ['if', 'unless']],
      [false, [], ['before']],
    ])
  })

  it('同じ名前のグループは使い、足りない語だけ末尾に足す', () => {
    const group = service.createGroup('条件')
    service.addWords(group.id, ['a1-0001'])
    run(input)
    expect(snapshot()).toEqual({ 条件: ['a.m.', 'if', 'unless'], 時: ['before'] })
    expect(service.listGroups().find((g) => g.name === '条件')?.id).toBe(group.id)
  })

  it('同じ綴りのマイ単語は中身を置き換え、ID はそのまま', () => {
    const old = service.createCustomWord({ ...unless, meaning: '〜でなければ', extraSenses: [] })
    clock = 2_000
    const reports = run(input)
    expect(service.listCustomWords()).toHaveLength(1)
    expect(service.getCustomWord(old.wordId).meaning).toBe(unless.meaning)
    expect(service.getGroup(service.listGroups()[0].id).wordIds).toContain(old.wordId)
    expect(reports[0].customReplaced).toEqual(['unless'])
    expect(reports[0].customCreated).toEqual([])
  })

  it('同じ語を 2 つのグループに入れると、マイ単語は 1 つだけ作る', () => {
    run({ groups: [{ name: 'A', words: [unless] }, { name: 'B', words: [unless] }] })
    expect(service.listCustomWords()).toHaveLength(1)
    expect(snapshot()).toEqual({ A: ['unless'], B: ['unless'] })
  })

  it('--dry-run は結果だけ返して何も書かない', () => {
    const reports = run(input, true)
    expect(reports.map((r) => r.added.length)).toEqual([2, 1])
    expect(service.listGroups()).toEqual([])
    expect(service.listCustomWords()).toEqual([])
    expect(formatReports(reports, true)).toContain('書き込んでいない')
  })

  it.each([
    ['単語帳に無い ID', { bundled: 'a1-9999', word: 'if' }, '単語帳に a1-9999 が無い'],
    ['ID と綴りが合わない', { bundled: 'a1-0452', word: 'when' }, 'a1-0452 は if'],
    ['品詞が無効', { ...unless, pos: 'verbish' }, 'unless: 品詞を選んでください'],
  ])('%sなら止めて、それまでの分も書かない', (_, word, message) => {
    expect(() => run({ groups: [input.groups[0], { name: '壊れた', words: [word] }] })).toThrow(message)
    expect(service.listGroups()).toEqual([])
    expect(service.listCustomWords()).toEqual([])
  })

  it('同じ名前のグループが複数あると止める', () => {
    service.createGroup('条件')
    service.createGroup('条件')
    expect(() => run(input)).toThrow(ImportInputError)
  })
})

describe('parseImportInput', () => {
  it('形が違えば場所を添えて止める', () => {
    expect(() => parseImportInput({})).toThrow('groups: 配列ではない')
    expect(() => parseImportInput({ groups: [{ name: 'x', words: [{ word: 'a', pos: 'noun' }] }] })).toThrow(
      'groups[0].words[0].meaning: 文字列ではない',
    )
  })

  it('例文・訳・2 つ目以降の意味は省ける', () => {
    expect(parseImportInput({ groups: [{ name: 'x', words: [{ word: 'a', pos: 'noun', meaning: 'エー' }] }] })).toEqual({
      groups: [{ name: 'x', words: [{ word: 'a', pos: 'noun', meaning: 'エー', example: '', exampleJa: '', extraSenses: [] }] }],
    })
  })
})

describe('data/groups/connectives.json', () => {
  it('そのまま取り込める（10 グループ・94 語・マイ単語 70）', () => {
    const file = path.resolve(import.meta.dirname, '../../../data/groups/connectives.json')
    const reports = run(parseImportInput(JSON.parse(readFileSync(file, 'utf8'))))
    expect(reports).toHaveLength(10)
    expect(reports.every((r) => r.created && r.alreadyIn.length === 0)).toBe(true)
    expect(reports.reduce((n, r) => n + r.added.length, 0)).toBe(94)
    expect(service.listCustomWords()).toHaveLength(70)
    expect(Object.values(snapshot()).flat()).not.toContainEqual(expect.stringMatching(/^custom-/))
  })
})
