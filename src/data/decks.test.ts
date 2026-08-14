import { readFileSync } from 'node:fs'
import { decks } from './decks'
import { findHeadword } from '../lib/inflect'
import type { PartOfSpeech, WordEntry } from './types'

const POS: PartOfSpeech[] = [
  'noun',
  'verb',
  'adjective',
  'adverb',
  'preposition',
  'conjunction',
  'interjection',
  'number',
  'determiner',
  'pronoun',
  'modal',
  'phrase',
]

const allWords: WordEntry[] = decks.flatMap((d) => d.words)

function readTsv(path: string): { word: string; pos: string; level: string }[] {
  return readFileSync(path, 'utf8')
    .trim()
    .split('\n')
    .slice(1)
    .map((line) => {
      const [word, pos, level] = line.split('\t')
      return { word, pos, level }
    })
}

describe('デッキデータ', () => {
  it('デッキ ID・名前が設定され、ID が一意である', () => {
    for (const deck of decks) {
      expect(deck.id).toBeTruthy()
      expect(deck.name).toBeTruthy()
      expect(deck.words.length).toBeGreaterThan(0)
    }
    expect(new Set(decks.map((d) => d.id)).size).toBe(decks.length)
  })

  it('全エントリが必須フィールドと形式を満たす', () => {
    for (const w of allWords) {
      expect(w.id, JSON.stringify(w)).toMatch(/^(a1|a2|ph)-\d{4}$/)
      expect(w.word.trim(), w.id).not.toBe('')
      expect(w.meaning.trim(), w.id).not.toBe('')
      expect(w.example.trim(), w.id).not.toBe('')
      expect(w.exampleJa.trim(), w.id).not.toBe('')
      expect(POS, `${w.id}: pos=${w.pos}`).toContain(w.pos)
      expect(['A1', 'A2'], `${w.id}: level=${w.level}`).toContain(w.level)
    }
  })

  it('ID と単語が全デッキを通して重複しない', () => {
    const ids = allWords.map((w) => w.id)
    expect(new Set(ids).size).toBe(ids.length)
    const words = allWords.map((w) => w.word.toLowerCase())
    expect(new Set(words).size).toBe(words.length)
  })

  it('A1/A2 デッキが抽出元 TSV と一致する（語・品詞・レベル・順序・連番）', () => {
    const sources = {
      a1: readTsv('data/source/cefrj-a1.tsv'),
      a2: readTsv('data/source/cefrj-a2.tsv'),
    }
    for (const prefix of ['a1', 'a2'] as const) {
      const expected = sources[prefix]
      const actual = decks
        .filter((d) => d.id.startsWith(`${prefix}-`))
        .flatMap((d) => d.words)
      expect(actual.length, `${prefix} 語数`).toBe(expected.length)
      actual.forEach((w, i) => {
        const src = expected[i]
        expect(w.word, w.id).toBe(src.word)
        expect(w.pos, w.id).toBe(src.pos)
        expect(w.level, w.id).toBe(src.level)
        expect(w.id).toBe(`${prefix}-${String(i + 1).padStart(4, '0')}`)
      })
    }
  })
})

/** 同じ値を持つエントリを「値 -> 単語一覧」の形で集める */
function duplicatesBy(pick: (w: WordEntry) => string): string[] {
  const groups = new Map<string, WordEntry[]>()
  for (const w of allWords) {
    const key = pick(w)
    groups.set(key, [...(groups.get(key) ?? []), w])
  }
  return [...groups]
    .filter(([, ws]) => ws.length > 1)
    .map(([key, ws]) => `${key} -> ${ws.map((w) => `${w.id} ${w.word}`).join(', ')}`)
}

describe('訳・例文の内容', () => {
  it('意味が全デッキを通して重複しない（4択で正解が複数になるため）', () => {
    expect(duplicatesBy((w) => w.meaning)).toEqual([])
  })

  it('例文が全デッキを通して重複しない', () => {
    expect(duplicatesBy((w) => w.example)).toEqual([])
  })

  it('例文が見出し語（活用形を含む）を含む', () => {
    const missing = allWords
      .filter((w) => !findHeadword(w.example, w.word))
      .map((w) => `${w.id} ${w.word} | ${w.example}`)
    expect(missing).toEqual([])
  })

  it('例文が初学者向けの短文に収まる（3〜12 語）', () => {
    const outOfRange = allWords
      .filter((w) => {
        const count = w.example.split(/\s+/).length
        return count < 3 || count > 12
      })
      .map((w) => `${w.id} ${w.word} | ${w.example}`)
    expect(outOfRange).toEqual([])
  })

  it('意味は 2 個まで（「／」区切り）', () => {
    const tooMany = allWords
      .filter((w) => w.meaning.split('／').length > 2)
      .map((w) => `${w.id} ${w.word} | ${w.meaning}`)
    expect(tooMany).toEqual([])
  })

  it('例文訳が句点で終わる', () => {
    const bad = allWords
      .filter((w) => !/[。？！]$/.test(w.exampleJa.trim()))
      .map((w) => `${w.id} ${w.word} | ${w.exampleJa}`)
    expect(bad).toEqual([])
  })
})
