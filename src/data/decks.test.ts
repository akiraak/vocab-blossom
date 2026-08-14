import { readFileSync } from 'node:fs'
import { decks } from './decks'
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
