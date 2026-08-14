export type CefrLevel = 'A1' | 'A2'

export type PartOfSpeech =
  | 'noun'
  | 'verb'
  | 'adjective'
  | 'adverb'
  | 'preposition'
  | 'conjunction'
  | 'interjection'
  | 'number'
  | 'determiner'
  | 'pronoun'
  | 'modal'
  | 'phrase'

export interface WordEntry {
  /** レベル別連番（例: "a1-0001"）。学習進捗のキーになるため公開後は不変 */
  id: string
  word: string
  pos: PartOfSpeech
  level: CefrLevel
  /** 日本語の意味。複数は「／」区切りで 2 個まで */
  meaning: string
  example: string
  exampleJa: string
}

export interface Deck {
  id: string
  name: string
  words: WordEntry[]
}
