import fs from 'node:fs'
import path from 'node:path'
import type { PartOfSpeech } from '../sync/types.ts'

// 同梱語（アプリに最初から入っている語）。アプリと同じ data/decks/*.json を起動時に読む。
// 管理画面では表示・検索・グループへの出し入れだけに使い、中身は編集しない。

export type BundledWord = {
  id: string
  word: string
  pos: PartOfSpeech
  level: string
  meaning: string
  example: string
  exampleJa: string
  /** デッキ名（A1 前半 など） */
  deckName: string
}

/** コンテナでもリポジトリでも server/src/words から見て ../../../data/decks */
export const DEFAULT_DECKS_DIR = path.resolve(import.meta.dirname, '../../../data/decks')

export const SEARCH_LIMIT = 50

/** 綴りの比較用（iOS の WordStore.normalizedSpelling と同じ: 前後の空白を落として小文字） */
export function normalizeSpelling(text: string): string {
  return text.trim().toLowerCase()
}

type DeckFile = {
  name: string
  words: Omit<BundledWord, 'deckName'>[]
}

export class BundledWords {
  readonly all: readonly BundledWord[]
  private readonly byId: Map<string, BundledWord>

  constructor(words: BundledWord[]) {
    this.all = words
    this.byId = new Map(words.map((w) => [w.id, w]))
  }

  /** デッキの JSON をファイル名の順に読む */
  static load(dir: string = DEFAULT_DECKS_DIR): BundledWords {
    const files = fs
      .readdirSync(dir)
      .filter((name) => name.endsWith('.json'))
      .sort()
    const words = files.flatMap((name) => {
      const deck = JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8')) as DeckFile
      return deck.words.map((w) => ({ ...w, deckName: deck.name }))
    })
    return new BundledWords(words)
  }

  get(id: string): BundledWord | null {
    return this.byId.get(id) ?? null
  }

  has(id: string): boolean {
    return this.byId.has(id)
  }

  /** 同じ綴りの同梱語（最初の 1 つ） */
  findBySpelling(text: string): BundledWord | null {
    const key = normalizeSpelling(text)
    if (key === '') return null
    return this.all.find((w) => normalizeSpelling(w.word) === key) ?? null
  }

  /** 英語の前方一致 → 英語の部分一致 → 意味の部分一致の順に、最大 limit 件 */
  search(query: string, limit: number = SEARCH_LIMIT): BundledWord[] {
    return searchWords(this.all, query, limit)
  }
}

/** extraSenses は自作語の 2 つ目以降の意味（意味・例文の検索の対象にする） */
type Searchable = {
  word: string
  meaning: string
  example?: string
  extraSenses?: readonly { meaning: string; example?: string }[]
}

/**
 * 同梱語・自作語の共通の検索。iOS の `WordStore.filter` と同じ並び:
 * 英語の完全一致 → 前方一致 → 部分一致 → 意味（2 つ目以降の意味も）→ 例文（同じく）。同じ順位では元の並び
 */
export function searchWords<T extends Searchable>(
  words: readonly T[],
  query: string,
  limit: number = SEARCH_LIMIT,
): T[] {
  const q = normalizeSpelling(query)
  if (q === '') return []
  const contains = (text: string | undefined) => (text ?? '').toLowerCase().includes(q)
  const ranked: { word: T; rank: number; index: number }[] = []
  words.forEach((word, index) => {
    const spelling = normalizeSpelling(word.word)
    const senses = [word, ...(word.extraSenses ?? [])]
    let rank: number
    if (spelling === q) rank = 0
    else if (spelling.startsWith(q)) rank = 1
    else if (spelling.includes(q)) rank = 2
    else if (senses.some((s) => contains(s.meaning))) rank = 3
    else if (senses.some((s) => contains(s.example))) rank = 4
    else return
    ranked.push({ word, rank, index })
  })
  ranked.sort((a, b) => a.rank - b.rank || a.index - b.index)
  return ranked.slice(0, limit).map((r) => r.word)
}
