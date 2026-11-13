import type { DB, Migration } from '../db.ts'
import { InvalidJsonError, PayloadTooLargeError, readJson } from '../http/body.ts'
import { json } from '../http/responses.ts'
import type { Handler } from '../http/router.ts'
import { PARTS_OF_SPEECH, type PartOfSpeech } from '../sync/types.ts'
import { countHeadword } from '../words/inflect.ts'
import type { RateLimiter } from './word-assist.ts'
import { CLAUDE_MODELS, type ClaudeModel, ModelInputError, parseModel } from './models.ts'

// 穴埋め用の文章（POST /api/passages）。1 語につき 3 パターンを AI で作り、「綴り・品詞・意味」を鍵にためる。
// iOS はグループで穴埋めを始めるたびに、全語を refresh 付きで送って作り直す（同じ文章を出さないため）。
// refresh が無ければ、ためた文章を返し、無い語だけ作る。設計は docs/plans/fill-blank-passages.md・fill-blank-typing.md。

export const PASSAGES_BODY_LIMIT = 16 * 1024
/** 1 回に送れる語数。AI の 1 回の呼び出しが iOS の待てる時間に収まる量 */
export const MAX_WORDS_PER_REQUEST = 5
export const PASSAGES_PER_WORD = 3
export const MIN_PASSAGE_WORDS = 12
export const MAX_PASSAGE_WORDS = 45
const MAX_FIELD_LENGTH = 300

/** 1 パターン分。text の見出し語を空欄にして出し、答えたあと ja を見せる */
export type Passage = { text: string; ja: string }

/** 文章を作る語（iOS から届く）。id は iOS が結果を受け取るための目印で、サーバーは中身を見ない */
export type PassageWord = {
  id: string
  word: string
  pos: PartOfSpeech
  meaning: string
  example: string
  /** 作り直すとき、前にためてあった文章（サーバーが入れる）。AI にこれと違う文章を書かせ、同じなら検証で落とす */
  avoid?: string[]
}

/** AI が返す 1 語分 */
export type GeneratedPassages = { id: string; passages: Passage[] }

export type PassagesResponse = { results: { id: string; passages: Passage[] }[] }

/** AI の呼び出し。本番は claude-passages.ts、テストは偽物に差し替える */
export type PassageWriter = {
  /** model を省いたら env（無ければ既定）のモデル */
  write: (words: PassageWord[], model?: ClaudeModel) => Promise<GeneratedPassages[]>
}

export class PassagesInputError extends Error {}

export const PASSAGES_MIGRATION: Migration = {
  name: 'word-passages',
  up: (db) => {
    db.exec(`
      CREATE TABLE word_passages (
        key TEXT PRIMARY KEY,
        passages TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    `)
  },
}

// MARK: - 検証

export function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length
}

/** 文の数（. ! ? で区切る。Mr. などの略語は A1〜A2 の文章ではまず出ないので考えない） */
export function sentenceCount(text: string): number {
  return text.split(/[.!?]+(?:\s|$)/).filter((part) => part.trim() !== '').length
}

/** 1 語分の文章の問題点。問題が無ければ空配列 */
export function passageProblems(
  word: { word: string; example: string; avoid?: string[] },
  passages: Passage[],
): string[] {
  const problems: string[] = []
  if (passages.length !== PASSAGES_PER_WORD) {
    problems.push(`パターンが ${passages.length} 個（${PASSAGES_PER_WORD} 個にする）`)
  }
  const seen = new Set<string>()
  passages.forEach((passage, index) => {
    const label = `${index + 1} 個目`
    const text = passage.text.trim()
    const count = countHeadword(text, word.word)
    if (count !== 1) problems.push(`${label}: 見出し語が ${count} 回（1 回にする）`)
    const words = wordCount(text)
    if (words < MIN_PASSAGE_WORDS || words > MAX_PASSAGE_WORDS) {
      problems.push(`${label}: ${words} 語（${MIN_PASSAGE_WORDS}〜${MAX_PASSAGE_WORDS} 語にする）`)
    }
    const sentences = sentenceCount(text)
    if (sentences < 2 || sentences > 4) problems.push(`${label}: ${sentences} 文（2〜4 文にする）`)
    const example = word.example.trim()
    if (example !== '' && text.includes(example)) problems.push(`${label}: 単語カードの例文をそのまま使っている`)
    if (!/[。？！]$/.test(passage.ja.trim())) problems.push(`${label}: 和訳が句点で終わっていない`)
    if (seen.has(text)) problems.push(`${label}: ほかのパターンと同じ文章`)
    if (word.avoid?.some((previous) => previous.trim() === text)) problems.push(`${label}: 前の文章と同じ`)
    seen.add(text)
  })
  return problems
}

// MARK: - 入力

function requireString(item: Record<string, unknown>, field: string, index: number, allowEmpty = false): string {
  const value = item[field]
  if (typeof value !== 'string') throw new PassagesInputError(`words[${index}].${field} がありません`)
  const trimmed = value.trim()
  if (!allowEmpty && trimmed === '') throw new PassagesInputError(`words[${index}].${field} が空です`)
  if (trimmed.length > MAX_FIELD_LENGTH) throw new PassagesInputError(`words[${index}].${field} が長すぎます`)
  return trimmed
}

export function parsePassagesInput(body: unknown): PassageWord[] {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new PassagesInputError('JSON のオブジェクトで送ってください')
  }
  const words = (body as Record<string, unknown>).words
  if (!Array.isArray(words) || words.length === 0) throw new PassagesInputError('words がありません')
  if (words.length > MAX_WORDS_PER_REQUEST) {
    throw new PassagesInputError(`words は ${MAX_WORDS_PER_REQUEST} 語までです`)
  }
  return words.map((value, index) => {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      throw new PassagesInputError(`words[${index}] がオブジェクトではありません`)
    }
    const item = value as Record<string, unknown>
    const pos = requireString(item, 'pos', index)
    if (!(PARTS_OF_SPEECH as readonly string[]).includes(pos)) {
      throw new PassagesInputError(`words[${index}].pos が不正です`)
    }
    return {
      id: requireString(item, 'id', index),
      word: requireString(item, 'word', index),
      pos: pos as PartOfSpeech,
      meaning: requireString(item, 'meaning', index),
      example: requireString(item, 'example', index, true),
    }
  })
}

/** 作り直すか（refresh）。無ければ false、真偽値でなければ弾く */
export function parseRefresh(body: unknown): boolean {
  const refresh = (body as Record<string, unknown>).refresh
  if (refresh === undefined || refresh === null) return false
  if (typeof refresh !== 'boolean') throw new PassagesInputError('refresh が真偽値ではありません')
  return refresh
}

// MARK: - ためる

/** 鍵は「綴り（小文字）・品詞・意味」。意味を直したマイ単語は別の鍵になり、作り直す */
export function passageKey(word: Pick<PassageWord, 'word' | 'pos' | 'meaning'>): string {
  return [word.word.trim().toLowerCase(), word.pos, word.meaning.trim()].join('\t')
}

export class PassageStore {
  private readonly db: DB

  constructor(db: DB) {
    this.db = db
  }

  get(key: string): Passage[] | null {
    const row = this.db.prepare('SELECT passages FROM word_passages WHERE key = ?').get(key) as
      | { passages: string }
      | undefined
    return row ? (JSON.parse(row.passages) as Passage[]) : null
  }

  put(key: string, passages: Passage[], now: number): void {
    this.db
      .prepare(
        `INSERT INTO word_passages (key, passages, created_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET passages = excluded.passages, created_at = excluded.created_at`,
      )
      .run(key, JSON.stringify(passages), now)
  }
}

// MARK: - ハンドラ

export type PassagesDeps = {
  writer: PassageWriter | null
  store: PassageStore
  limiter: RateLimiter
  now: () => number
  logError: (message: string, error?: unknown) => void
}

/** AI の返事から、検証を通った語だけ取り出す（返事の文字列は前後の空白を落とす）。通らなかった理由は rejected に入れる */
function acceptedPassages(
  words: PassageWord[],
  generated: GeneratedPassages[],
): { accepted: Map<string, Passage[]>; rejected: string[] } {
  const accepted = new Map<string, Passage[]>()
  const rejected: string[] = []
  for (const word of words) {
    const item = generated.find((g) => g.id === word.id)
    if (!item) {
      rejected.push(`${word.word}: 返事に無い`)
      continue
    }
    const passages = item.passages.map((p) => ({ text: p.text.trim(), ja: p.ja.trim() }))
    const problems = passageProblems(word, passages)
    if (problems.length === 0) accepted.set(word.id, passages)
    else rejected.push(`${word.word}: ${problems.join(' / ')}`)
  }
  return { accepted, rejected }
}

export function passagesHandler({ writer, store, limiter, now, logError }: PassagesDeps): Handler {
  return async (request) => {
    let words: PassageWord[]
    let model: ClaudeModel | undefined
    let refresh: boolean
    try {
      const body = await readJson(request, PASSAGES_BODY_LIMIT)
      words = parsePassagesInput(body)
      refresh = parseRefresh(body)
      model = parseModel(body, CLAUDE_MODELS)
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return json({ error: 'payload too large' }, 413)
      if (error instanceof InvalidJsonError || error instanceof PassagesInputError || error instanceof ModelInputError) {
        return json({ error: error.message }, 400)
      }
      throw error
    }

    // refresh なら、ためた文章があっても作り直す。前の文章は AI に渡して、違う文章を書かせる。
    // 作れなかった語は空で返し、ためた文章は消さない（端末は手元の前の文章で出す）
    const found = new Map<string, Passage[]>()
    words = words.map((word) => {
      const cached = store.get(passageKey(word))
      if (!cached) return word
      if (!refresh) {
        found.set(word.id, cached)
        return word
      }
      return { ...word, avoid: cached.map((passage) => passage.text) }
    })

    let missing = words.filter((word) => !found.has(word.id))
    if (missing.length > 0) {
      if (!writer) return json({ error: 'ai-unavailable' }, 503)
      // 検証に通らなかった語だけ、もう 1 回だけ作り直す
      for (let attempt = 0; attempt < 2 && missing.length > 0; attempt++) {
        if (!limiter.take()) {
          if (attempt === 0) return json({ error: 'rate-limited' }, 429, { 'retry-after': '60' })
          break
        }
        let generated: GeneratedPassages[]
        try {
          generated = await writer.write(missing, model)
        } catch (error) {
          logError('[passages] AI の呼び出しに失敗', error)
          if (attempt === 0) return json({ error: 'ai-failed' }, 502)
          break
        }
        const { accepted, rejected } = acceptedPassages(missing, generated)
        if (rejected.length > 0) logError(`[passages] 検証に通らなかった語: ${rejected.join('; ')}`)
        for (const [id, passages] of accepted) {
          const word = missing.find((w) => w.id === id)!
          store.put(passageKey(word), passages, now())
          found.set(id, passages)
        }
        missing = missing.filter((word) => !found.has(word.id))
      }
    }

    const body: PassagesResponse = {
      results: words.map((word) => ({ id: word.id, passages: found.get(word.id) ?? [] })),
    }
    return json(body)
  }
}
