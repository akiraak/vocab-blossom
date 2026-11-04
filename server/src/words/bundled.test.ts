import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { testBundled } from '../test-helpers.ts'
import { BundledWords, DEFAULT_DECKS_DIR, normalizeSpelling, searchWords } from './bundled.ts'

const word = (id: string, w: string, meaning: string) => ({
  id,
  word: w,
  meaning,
  pos: 'noun' as const,
  level: 'A1',
  example: '',
  exampleJa: '',
  deckName: 'test',
})

describe('BundledWords.load', () => {
  it('data/decks の全デッキを読む', () => {
    const bundled = testBundled()
    const expected = fs
      .readdirSync(DEFAULT_DECKS_DIR)
      .filter((name) => name.endsWith('.json'))
      .reduce((sum, name) => {
        const deck = JSON.parse(fs.readFileSync(path.join(DEFAULT_DECKS_DIR, name), 'utf8'))
        return sum + deck.words.length
      }, 0)
    expect(bundled.all.length).toBe(expected)
    expect(bundled.get('a1-0001')).toMatchObject({ word: 'a.m.', deckName: 'A1 前半' })
    expect(bundled.get('ph-0001')).toMatchObject({ word: 'get up', pos: 'phrase' })
    expect(bundled.get('custom-x')).toBeNull()
  })
})

describe('findBySpelling', () => {
  it('前後の空白・大小文字を無視して同じ綴りを探す', () => {
    const bundled = new BundledWords([word('a', 'Action', '行動'), word('b', 'actor', '俳優')])
    expect(bundled.findBySpelling('  action ')?.id).toBe('a')
    expect(bundled.findBySpelling('act')).toBeNull()
    expect(bundled.findBySpelling('   ')).toBeNull()
  })
})

describe('searchWords', () => {
  const words = [
    word('1', 'react', '反応する'),
    word('2', 'act', '行動する'),
    word('3', 'action', '行動'),
    word('4', 'fact', '事実'),
    word('5', 'deed', '行い（act）'),
  ]

  it('英語の完全一致 → 前方一致 → 部分一致 → 意味 → 例文の順（iOS の WordStore.filter と同じ）', () => {
    const list = [
      word('0', 'actor', '俳優'),
      ...words,
      { ...word('6', 'play', '演じる'), example: 'Let us act it out.' },
    ]
    expect(searchWords(list, 'act').map((w) => w.id)).toEqual(['2', '0', '3', '1', '4', '5', '6'])
  })

  it('2 つ目以降の意味・例文でも探せる', () => {
    const commute = {
      ...word('c', 'commute', '通勤する'),
      extraSenses: [{ meaning: '通学', example: 'My daily trip is long.' }],
    }
    expect(searchWords([commute], '通学').map((w) => w.id)).toEqual(['c'])
    expect(searchWords([commute], 'daily trip').map((w) => w.id)).toEqual(['c'])
  })

  it('大小文字・前後の空白を無視し、日本語の意味でも探せる', () => {
    expect(searchWords(words, ' ACT ').length).toBe(5)
    expect(searchWords(words, '行動').map((w) => w.id)).toEqual(['2', '3'])
  })

  it('空の検索語は何も返さない・件数の上限', () => {
    expect(searchWords(words, '  ')).toEqual([])
    expect(searchWords(words, 'act', 2).map((w) => w.id)).toEqual(['2', '3'])
  })

  it('normalizeSpelling', () => {
    expect(normalizeSpelling('  Take Care Of ')).toBe('take care of')
  })
})
