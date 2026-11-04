import { InvalidJsonError, PayloadTooLargeError, readJson } from '../http/body.ts'
import { json } from '../http/responses.ts'
import type { Handler } from '../http/router.ts'
import { PARTS_OF_SPEECH, type PartOfSpeech } from '../sync/types.ts'
import { type BundledWords, normalizeSpelling } from '../words/bundled.ts'

// 自作語を作る前の AI チェック（POST /api/word-assist・POST /admin/word-assist）。
// 入力（英語でも日本語でもよい）を AI に見てもらい、打ち間違い・活用形・日本語での入力などを同梱語に寄せる。
// 同梱語に無い語だけ、意味・品詞・例文の下書きを返して自作語にしてもらう。
// 設計は docs/plans/ai-word-assist.md。

export const WORD_ASSIST_BODY_LIMIT = 4 * 1024
export const MAX_INPUT_LENGTH = 60
/** 品詞の違う候補（commute の動詞・名詞）も 1 件と数えるので、別の語の候補と合わせて入るよう 5 件まで */
export const MAX_CANDIDATES = 5

export const ASSIST_REASONS = ['exact', 'typo', 'inflection', 'variant', 'translation'] as const
export type AssistReason = (typeof ASSIST_REASONS)[number]

/** AI が返す候補（同梱語との照合前） */
export type AiCandidate = {
  word: string
  pos: PartOfSpeech
  meaning: string
  example: string
  exampleJa: string
  reason: AssistReason
}

export type BundledMatch = {
  id: string
  word: string
  meaning: string
  pos: PartOfSpeech
  level: string
}

export type AssistCandidate = AiCandidate & { bundled: BundledMatch | null }

export type WordAssistResponse = {
  text: string
  candidates: AssistCandidate[]
}

/** AI の呼び出し。本番は claude.ts、テストは偽物に差し替える */
export type WordAssistant = {
  suggest: (text: string) => Promise<AiCandidate[]>
}

/** AI が答えられなかった（通信失敗・拒否・形式違い）。502 にする */
export class WordAssistError extends Error {}

export class InputError extends Error {}

export function parseAssistInput(body: unknown): string {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new InputError('JSON のオブジェクトで送ってください')
  }
  const value = (body as Record<string, unknown>).text
  if (typeof value !== 'string') throw new InputError('text がありません')
  const text = value.trim().replace(/\s+/g, ' ')
  if (text === '') throw new InputError('text が空です')
  if ([...text].length > MAX_INPUT_LENGTH) throw new InputError(`text は ${MAX_INPUT_LENGTH} 文字までです`)
  return text
}

/**
 * AI の候補を同梱語と綴りで照合する。
 *
 * 単語帳に無い語は、品詞の違う候補（commute の動詞・名詞）を残す（アプリが 1 つの自作語の意味としてまとめる）。
 * 同じ綴り・同じ品詞の候補と、単語帳にある語の 2 つ目以降の候補（案内は 1 つで足りる）は落とす。
 * AI が「単語帳にある」と言っても、照合できなければ自作語の候補として扱う（同梱語の ID を AI に作らせない）
 */
export function resolveCandidates(candidates: readonly AiCandidate[], bundled: BundledWords): AssistCandidate[] {
  const seen = new Set<string>()
  const resolved: AssistCandidate[] = []
  for (const candidate of candidates) {
    const word = candidate.word.trim()
    const spelling = normalizeSpelling(word)
    if (spelling === '') continue
    const hit = bundled.findBySpelling(word)
    // 単語帳の語は綴りごとに 1 つ、単語帳に無い語は綴り・品詞ごとに 1 つ
    const key = hit ? spelling : `${spelling} ${candidate.pos}`
    if (seen.has(key)) continue
    seen.add(key)
    resolved.push({
      ...candidate,
      word,
      meaning: candidate.meaning.trim(),
      example: candidate.example.trim(),
      exampleJa: candidate.exampleJa.trim(),
      bundled: hit ? { id: hit.id, word: hit.word, meaning: hit.meaning, pos: hit.pos, level: hit.level } : null,
    })
    if (resolved.length >= MAX_CANDIDATES) break
  }
  return resolved
}

/** AI の返した JSON を検証する（構造化出力で形は守られるが、念のため型と値を確かめる） */
export function parseAiOutput(value: unknown): AiCandidate[] {
  const candidates = (value as { candidates?: unknown } | null)?.candidates
  if (!Array.isArray(candidates)) throw new WordAssistError('AI の返事に candidates がありません')
  const result: AiCandidate[] = []
  for (const item of candidates) {
    if (typeof item !== 'object' || item === null) continue
    const c = item as Record<string, unknown>
    const strings = ['word', 'meaning', 'example', 'exampleJa'].every((k) => typeof c[k] === 'string')
    if (!strings) continue
    if (!PARTS_OF_SPEECH.includes(c.pos as PartOfSpeech)) continue
    if (!ASSIST_REASONS.includes(c.reason as AssistReason)) continue
    if ((c.word as string).trim() === '' || (c.meaning as string).trim() === '') continue
    result.push({
      word: c.word as string,
      pos: c.pos as PartOfSpeech,
      meaning: c.meaning as string,
      example: c.example as string,
      exampleJa: c.exampleJa as string,
      reason: c.reason as AssistReason,
    })
  }
  if (result.length === 0) throw new WordAssistError('AI の返事に使える候補がありません')
  return result
}

/** 決まった時間の窓で回数を数える簡単な制限（サーバー全体で 1 つ。漏れた共有シークレットで請求が膨らまないように） */
export class RateLimiter {
  private hits: number[] = []
  private readonly limit: number
  private readonly windowMs: number
  private readonly now: () => number

  constructor(limit: number, windowMs: number, now: () => number = Date.now) {
    this.limit = limit
    this.windowMs = windowMs
    this.now = now
  }

  /** 使えるなら数えて true */
  take(): boolean {
    const now = this.now()
    this.hits = this.hits.filter((t) => now - t < this.windowMs)
    if (this.hits.length >= this.limit) return false
    this.hits.push(now)
    return true
  }
}

export const RATE_LIMIT = 60
export const RATE_WINDOW_MS = 10 * 60 * 1000

export type WordAssistDeps = {
  /** null ならキー未設定（503） */
  assistant: WordAssistant | null
  bundled: BundledWords
  limiter: RateLimiter
  logError: (message: string, error?: unknown) => void
}

/** 入力を受けて候補を返す。iOS 用と管理画面用で同じ関数を使う */
export function wordAssistHandler({ assistant, bundled, limiter, logError }: WordAssistDeps): Handler {
  return async (request) => {
    if (!assistant) return json({ error: 'ai-unavailable' }, 503)

    let text: string
    try {
      text = parseAssistInput(await readJson(request, WORD_ASSIST_BODY_LIMIT))
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return json({ error: 'payload too large' }, 413)
      if (error instanceof InvalidJsonError || error instanceof InputError) {
        return json({ error: error.message }, 400)
      }
      throw error
    }

    if (!limiter.take()) return json({ error: 'rate-limited' }, 429, { 'retry-after': '60' })

    let candidates: AiCandidate[]
    try {
      candidates = await assistant.suggest(text)
    } catch (error) {
      logError('[word-assist] AI の呼び出しに失敗', error)
      return json({ error: 'ai-failed' }, 502)
    }

    const body: WordAssistResponse = { text, candidates: resolveCandidates(candidates, bundled) }
    return json(body)
  }
}
