import { decks } from '../data/decks'
import type { CefrLevel, Deck, PartOfSpeech, WordEntry } from '../data/types'

export { decks }

export const allWords: WordEntry[] = decks.flatMap((deck) => deck.words)

const byId = new Map(allWords.map((word) => [word.id, word]))
const deckIdByWordId = new Map(
  decks.flatMap((deck) => deck.words.map((word) => [word.id, deck.id] as const)),
)

export function getWord(id: string): WordEntry | undefined {
  return byId.get(id)
}

export function getDeckOf(wordId: string): Deck | undefined {
  const deckId = deckIdByWordId.get(wordId)
  return decks.find((deck) => deck.id === deckId)
}

export function wordsOfLevel(level: CefrLevel): WordEntry[] {
  return allWords.filter((word) => word.level === level)
}

export const POS_LABEL: Record<PartOfSpeech, string> = {
  noun: '名詞',
  verb: '動詞',
  adjective: '形容詞',
  adverb: '副詞',
  preposition: '前置詞',
  conjunction: '接続詞',
  interjection: '間投詞',
  number: '数詞',
  determiner: '限定詞',
  pronoun: '代名詞',
  modal: '助動詞',
  phrase: '熟語',
}
