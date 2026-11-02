import { describe, expect, it } from 'vitest'
import { ValidationError, parseSyncRequest } from './types.ts'

const GROUP_ID = '3F2504E0-4F89-11D3-9A0C-0305E82C3301'

const group = (overrides: Record<string, unknown> = {}) => ({
  id: GROUP_ID,
  name: ' 旅行 ',
  wordIds: ['a1-apple', 'custom-x', 'a1-apple'],
  createdAt: 1,
  updatedAt: 2,
  ...overrides,
})

const customWord = (overrides: Record<string, unknown> = {}) => ({
  wordId: 'custom-x',
  word: 'boarding pass',
  meaning: '搭乗券',
  pos: 'phrase',
  example: '',
  exampleJa: '',
  createdAt: 1,
  updatedAt: 2,
  ...overrides,
})

describe('parseSyncRequest', () => {
  it('配列は省略でき、cursor も省略すると 0', () => {
    expect(parseSyncRequest({})).toEqual({ cursor: 0, groups: [], customWords: [], deletions: [] })
  })

  it('グループの ID を小文字にそろえ、名前を trim し、単語 ID の重複を除く', () => {
    const parsed = parseSyncRequest({ cursor: 3, groups: [group()] })
    expect(parsed.cursor).toBe(3)
    expect(parsed.groups[0]).toEqual({
      id: GROUP_ID.toLowerCase(),
      name: '旅行',
      wordIds: ['a1-apple', 'custom-x'],
      createdAt: 1,
      updatedAt: 2,
    })
  })

  it('自作語の例文・例文訳は省略すると空文字', () => {
    const { example: _e, exampleJa: _j, ...rest } = customWord()
    const parsed = parseSyncRequest({ customWords: [rest] })
    expect(parsed.customWords[0]).toMatchObject({ example: '', exampleJa: '' })
  })

  it('削除記録のグループ ID も小文字にそろえる', () => {
    const parsed = parseSyncRequest({
      deletions: [
        { kind: 'group', id: GROUP_ID, deletedAt: 5 },
        { kind: 'customWord', id: 'custom-x', deletedAt: 6 },
      ],
    })
    expect(parsed.deletions).toEqual([
      { kind: 'group', id: GROUP_ID.toLowerCase(), deletedAt: 5 },
      { kind: 'customWord', id: 'custom-x', deletedAt: 6 },
    ])
  })

  it.each([
    ['本文が配列', []],
    ['cursor が負', { cursor: -1 }],
    ['cursor が小数', { cursor: 1.5 }],
    ['groups が配列でない', { groups: {} }],
    ['グループ ID が UUID でない', { groups: [group({ id: 'abc' })] }],
    ['グループ名が空', { groups: [group({ name: '  ' })] }],
    ['wordIds が無い', { groups: [group({ wordIds: undefined })] }],
    ['wordIds に数値', { groups: [group({ wordIds: [1] })] }],
    ['updatedAt が文字列', { groups: [group({ updatedAt: '2026-11-02' })] }],
    ['自作語 ID が custom- で始まらない', { customWords: [customWord({ wordId: 'a1-apple' })] }],
    ['自作語 ID が custom- だけ', { customWords: [customWord({ wordId: 'custom-' })] }],
    ['品詞が不明', { customWords: [customWord({ pos: 'verbs' })] }],
    ['意味が空', { customWords: [customWord({ meaning: '' })] }],
    ['英語が長すぎる', { customWords: [customWord({ word: 'a'.repeat(201) })] }],
    ['削除の種類が不明', { deletions: [{ kind: 'progress', id: 'x', deletedAt: 1 }] }],
    ['自作語の削除の ID が custom- で始まらない', { deletions: [{ kind: 'customWord', id: 'a1-apple', deletedAt: 1 }] }],
  ])('%s なら ValidationError', (_label, body) => {
    expect(() => parseSyncRequest(body)).toThrow(ValidationError)
  })

  it('エラーメッセージにどこが悪いかが入る', () => {
    expect(() => parseSyncRequest({ customWords: [customWord(), customWord({ pos: 'x' })] })).toThrow(
      'customWords[1].pos',
    )
  })
})
