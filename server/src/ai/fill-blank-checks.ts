import type { DB, Migration } from '../db.ts'
import { InvalidJsonError, PayloadTooLargeError, readJson } from '../http/body.ts'
import { json } from '../http/responses.ts'
import type { Handler } from '../http/router.ts'
import { findHeadword } from '../words/inflect.ts'
import type { RateLimiter } from './word-assist.ts'
import { CLAUDE_MODELS, type ClaudeModel, ModelInputError, parseModel } from './models.ts'

// 穴埋めの選択肢の判定（POST /api/fill-blank-checks）。iOS がグループの穴埋めを始める前に、組み立てた問題
// （文章 + 正解 + 誤答肢）を送り、誤答肢のうち空欄に入れても正しい文になる語（ほかの正解）を返す。
// 判定は「文章・正解・選択肢の語」ごとにためて、同じ組では AI を呼ばない。設計は docs/plans/connective-fill-blank-check.md。

export const CHECKS_BODY_LIMIT = 32 * 1024
/** 1 回に送れる問題数。グループ 1 つ分（10 語前後）を 1 回で判定できる量 */
export const MAX_ITEMS_PER_REQUEST = 10
/** 1 問の誤答肢の数の上限（4 択なので 3） */
export const MAX_CHOICES = 3
const MAX_TEXT_LENGTH = 600
const MAX_WORD_LENGTH = 100
/** AI に見せる空欄 */
export const BLANK = '_____'

/** 判定する 1 問（iOS から届く）。text は見出し語の入った全文、choices は正解以外の選択肢 */
export type CheckItem = {
  id: string
  text: string
  answer: string
  choices: string[]
}

export type ChecksResponse = { results: { id: string; alsoCorrect: string[] }[] }

/** AI に判定させる 1 問。blanked は見出し語を空欄にした文章、candidates はまだ判定していない選択肢 */
export type CheckQuestion = {
  id: string
  blanked: string
  answer: string
  candidates: string[]
}

/** AI の判定 1 問分。fits は空欄に入る語（candidates のうち） */
export type CheckVerdict = { id: string; verdicts: { word: string; fits: boolean }[] }

/** AI の呼び出し。本番は claude-fill-blank-check.ts、テストは偽物に差し替える */
export type ChoiceJudge = {
  /** model を省いたら env（無ければ既定）のモデル */
  judge: (questions: CheckQuestion[], model?: ClaudeModel) => Promise<CheckVerdict[]>
}

export class ChecksInputError extends Error {}

export const FILL_BLANK_CHECKS_MIGRATION: Migration = {
  name: 'fill-blank-checks',
  up: (db) => {
    db.exec(`
      CREATE TABLE fill_blank_checks (
        key TEXT PRIMARY KEY,
        fits INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    `)
  },
}

// MARK: - 入力

function requireString(value: unknown, label: string, maxLength: number): string {
  if (typeof value !== 'string') throw new ChecksInputError(`${label} がありません`)
  const trimmed = value.trim()
  if (trimmed === '') throw new ChecksInputError(`${label} が空です`)
  if (trimmed.length > maxLength) throw new ChecksInputError(`${label} が長すぎます`)
  return trimmed
}

export function parseChecksInput(body: unknown): CheckItem[] {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new ChecksInputError('JSON のオブジェクトで送ってください')
  }
  const items = (body as Record<string, unknown>).items
  if (!Array.isArray(items) || items.length === 0) throw new ChecksInputError('items がありません')
  if (items.length > MAX_ITEMS_PER_REQUEST) {
    throw new ChecksInputError(`items は ${MAX_ITEMS_PER_REQUEST} 問までです`)
  }
  return items.map((value, index) => {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      throw new ChecksInputError(`items[${index}] がオブジェクトではありません`)
    }
    const item = value as Record<string, unknown>
    const choices = item.choices
    if (!Array.isArray(choices) || choices.length === 0) throw new ChecksInputError(`items[${index}].choices がありません`)
    if (choices.length > MAX_CHOICES) throw new ChecksInputError(`items[${index}].choices は ${MAX_CHOICES} 語までです`)
    return {
      id: requireString(item.id, `items[${index}].id`, MAX_WORD_LENGTH),
      text: requireString(item.text, `items[${index}].text`, MAX_TEXT_LENGTH),
      answer: requireString(item.answer, `items[${index}].answer`, MAX_WORD_LENGTH),
      choices: choices.map((choice, c) => requireString(choice, `items[${index}].choices[${c}]`, MAX_WORD_LENGTH)),
    }
  })
}

/** 見出し語を空欄にした文章（「either … or …」は区切りごと）。見出し語が見つからなければ null */
export function blankPassage(text: string, answer: string): string | null {
  const match = findHeadword(text, answer)
  if (!match) return null
  let blanked = text
  for (const part of [...match.parts].reverse()) {
    blanked = blanked.slice(0, part.start) + BLANK + blanked.slice(part.end)
  }
  return blanked
}

// MARK: - ためる

const normalizeWord = (word: string) => word.trim().toLowerCase()

/** 鍵は「文章・正解（小文字）・選択肢（小文字）」 */
export function checkKey(text: string, answer: string, choice: string): string {
  return [text.trim(), normalizeWord(answer), normalizeWord(choice)].join('\t')
}

export class CheckStore {
  private readonly db: DB

  constructor(db: DB) {
    this.db = db
  }

  get(key: string): boolean | null {
    const row = this.db.prepare('SELECT fits FROM fill_blank_checks WHERE key = ?').get(key) as
      | { fits: number }
      | undefined
    return row ? row.fits === 1 : null
  }

  put(key: string, fits: boolean, now: number): void {
    this.db
      .prepare(
        `INSERT INTO fill_blank_checks (key, fits, created_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET fits = excluded.fits, created_at = excluded.created_at`,
      )
      .run(key, fits ? 1 : 0, now)
  }
}

// MARK: - ハンドラ

export type ChecksDeps = {
  judge: ChoiceJudge | null
  store: CheckStore
  limiter: RateLimiter
  now: () => number
  logError: (message: string, error?: unknown) => void
}

export function fillBlankChecksHandler({ judge, store, limiter, now, logError }: ChecksDeps): Handler {
  return async (request) => {
    let items: CheckItem[]
    let model: ClaudeModel | undefined
    try {
      const body = await readJson(request, CHECKS_BODY_LIMIT)
      items = parseChecksInput(body)
      model = parseModel(body, CLAUDE_MODELS)
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return json({ error: 'payload too large' }, 413)
      if (error instanceof InvalidJsonError || error instanceof ChecksInputError || error instanceof ModelInputError) {
        return json({ error: error.message }, 400)
      }
      throw error
    }

    // 判定済みの組（鍵 → 入るか）。ためてあるものから埋める
    const known = new Map<string, boolean>()
    const questions: CheckQuestion[] = []
    for (const item of items) {
      const candidates: string[] = []
      for (const choice of new Set(item.choices)) {
        if (normalizeWord(choice) === normalizeWord(item.answer)) continue
        const key = checkKey(item.text, item.answer, choice)
        const cached = store.get(key)
        if (cached === null) candidates.push(choice)
        else known.set(key, cached)
      }
      if (candidates.length === 0) continue
      const blanked = blankPassage(item.text, item.answer)
      if (!blanked) {
        // 空欄にできない文章は判定しない（ほかの正解なしで返す）
        logError(`[fill-blank-checks] 文章に見出し語が無い: ${item.answer}`)
        continue
      }
      questions.push({ id: item.id, blanked, answer: item.answer, candidates })
    }

    if (questions.length > 0) {
      if (!judge) return json({ error: 'ai-unavailable' }, 503)
      if (!limiter.take()) return json({ error: 'rate-limited' }, 429, { 'retry-after': '60' })
      let verdicts: CheckVerdict[]
      try {
        verdicts = await judge.judge(questions, model)
      } catch (error) {
        logError('[fill-blank-checks] AI の呼び出しに失敗', error)
        return json({ error: 'ai-failed' }, 502)
      }
      for (const question of questions) {
        const item = items.find((i) => i.id === question.id)!
        const verdict = verdicts.find((v) => v.id === question.id)
        for (const candidate of question.candidates) {
          const fits = verdict?.verdicts.find((v) => normalizeWord(v.word) === normalizeWord(candidate))?.fits
          // 返事に無い語はためない（次に送られたときに判定し直す）。今回はほかの正解にしない
          if (fits === undefined) continue
          const key = checkKey(item.text, item.answer, candidate)
          store.put(key, fits, now())
          known.set(key, fits)
        }
      }
    }

    const body: ChecksResponse = {
      results: items.map((item) => ({
        id: item.id,
        alsoCorrect: [...new Set(item.choices)].filter(
          (choice) =>
            normalizeWord(choice) !== normalizeWord(item.answer) &&
            known.get(checkKey(item.text, item.answer, choice)) === true,
        ),
      })),
    }
    return json(body)
  }
}
