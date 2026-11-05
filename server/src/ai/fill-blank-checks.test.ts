import { describe, expect, it } from 'vitest'
import { apiReq, createTestApp, req } from '../test-helpers.ts'
import { RATE_LIMIT } from './word-assist.ts'
import { checkUserMessage, parseCheckOutput } from './claude-fill-blank-check.ts'
import {
  BLANK,
  type CheckItem,
  type CheckQuestion,
  type ChecksResponse,
  ChecksInputError,
  type ChoiceJudge,
  MAX_CHOICES,
  MAX_ITEMS_PER_REQUEST,
  blankPassage,
  checkKey,
  parseChecksInput,
} from './fill-blank-checks.ts'

const moreover: CheckItem = {
  id: 'q1',
  text: 'This apartment is near the station. Moreover, the rent is low, so I want to live here.',
  answer: 'moreover',
  choices: ['however', 'besides', 'unless'],
}

const eitherOr: CheckItem = {
  id: 'q2',
  text: 'You can have either cake or ice cream after dinner.',
  answer: 'either … or …',
  choices: ['both … and …', 'neither … nor …'],
}

/** 呼ばれた問題を記録し、fits に入っている語だけ「入る」と返す偽物 */
function fakeJudge(
  fits: string[] | Error,
): ChoiceJudge & { calls: CheckQuestion[][]; models: (string | undefined)[] } {
  const calls: CheckQuestion[][] = []
  const models: (string | undefined)[] = []
  return {
    calls,
    models,
    async judge(questions, model) {
      calls.push(questions)
      models.push(model)
      if (fits instanceof Error) throw fits
      return questions.map((q) => ({
        id: q.id,
        verdicts: q.candidates.map((word) => ({ word, fits: fits.includes(word) })),
      }))
    },
  }
}

function checksReq(items: unknown, model?: unknown): Request {
  return apiReq('/api/fill-blank-checks', { method: 'POST', body: JSON.stringify({ items, model }) })
}

describe('blankPassage', () => {
  it('見出し語を空欄にする（活用形も）', () => {
    expect(blankPassage('She plays tennis every day.', 'play')).toBe(`She ${BLANK} tennis every day.`)
    expect(blankPassage(moreover.text, 'moreover')).toBe(
      `This apartment is near the station. ${BLANK}, the rent is low, so I want to live here.`,
    )
  })

  it('「…」を含む見出し語は区切りごとに空欄にする', () => {
    expect(blankPassage(eitherOr.text, eitherOr.answer)).toBe(`You can have ${BLANK} cake ${BLANK} ice cream after dinner.`)
  })

  it('見出し語が無ければ null', () => {
    expect(blankPassage('I like apples.', 'banana')).toBeNull()
  })
})

describe('parseChecksInput', () => {
  it('問題の一覧を受け取り、前後の空白を落とす', () => {
    expect(parseChecksInput({ items: [{ ...moreover, answer: ' moreover ' }] })).toEqual([moreover])
  })

  it('形が違えば ChecksInputError', () => {
    expect(() => parseChecksInput([])).toThrow(ChecksInputError)
    expect(() => parseChecksInput({ items: [] })).toThrow(ChecksInputError)
    expect(() => parseChecksInput({ items: [{ ...moreover, text: '' }] })).toThrow(ChecksInputError)
    expect(() => parseChecksInput({ items: [{ ...moreover, choices: [] }] })).toThrow(ChecksInputError)
    expect(() => parseChecksInput({ items: [{ ...moreover, choices: [1] }] })).toThrow(ChecksInputError)
    const tooManyChoices = Array.from({ length: MAX_CHOICES + 1 }, (_, i) => `w${i}`)
    expect(() => parseChecksInput({ items: [{ ...moreover, choices: tooManyChoices }] })).toThrow(ChecksInputError)
    const tooManyItems = Array.from({ length: MAX_ITEMS_PER_REQUEST + 1 }, (_, i) => ({ ...moreover, id: `q${i}` }))
    expect(() => parseChecksInput({ items: tooManyItems })).toThrow(ChecksInputError)
  })
})

describe('Claude の判定（形だけ）', () => {
  it('空欄にした文章・正解・まだ判定していない選択肢を 1 行ずつ送る', () => {
    const message = checkUserMessage([{ id: 'q1', blanked: `${BLANK}, it rained.`, answer: 'however', candidates: ['but'] }])
    expect(JSON.parse(message)).toEqual({ id: 'q1', passage: `${BLANK}, it rained.`, answer: 'however', choices: ['but'] })
  })

  it('返事から形の正しい判定だけ取り出す', () => {
    expect(
      parseCheckOutput({
        items: [
          { id: 'q1', verdicts: [{ word: 'besides', fits: true }, { word: 'unless', fits: 'no' }] },
          { id: 2, verdicts: [] },
        ],
      }),
    ).toEqual([{ id: 'q1', verdicts: [{ word: 'besides', fits: true }] }])
    expect(() => parseCheckOutput({})).toThrow()
  })
})

describe('POST /api/fill-blank-checks', () => {
  it('Bearer が無ければ 401', async () => {
    const { handle } = createTestApp({}, { choiceJudge: fakeJudge([]) })
    const res = await handle(req('/api/fill-blank-checks', { method: 'POST', body: JSON.stringify({ items: [moreover] }) }))
    expect(res.status).toBe(401)
  })

  it('入力が不正なら 400', async () => {
    const { handle } = createTestApp({}, { choiceJudge: fakeJudge([]) })
    expect((await handle(checksReq([]))).status).toBe(400)
    expect((await handle(checksReq([moreover], 'gpt-5'))).status).toBe(400)
  })

  it('空欄に入る誤答肢を alsoCorrect で返し、モデルを判定役に渡す', async () => {
    const judge = fakeJudge(['besides'])
    const { handle } = createTestApp({}, { choiceJudge: judge })
    const res = await handle(checksReq([moreover], 'claude-sonnet-5-5'))
    expect(res.status).toBe(200)
    expect((await res.json()) as ChecksResponse).toEqual({ results: [{ id: 'q1', alsoCorrect: ['besides'] }] })
    expect(judge.calls[0]).toEqual([
      {
        id: 'q1',
        blanked: `This apartment is near the station. ${BLANK}, the rent is low, so I want to live here.`,
        answer: 'moreover',
        candidates: ['however', 'besides', 'unless'],
      },
    ])
    expect(judge.models).toEqual(['claude-sonnet-5-5'])
  })

  it('判定をためて、同じ組では AI を呼ばない。新しい選択肢だけ判定する', async () => {
    const judge = fakeJudge(['besides', 'also'])
    const { handle } = createTestApp({}, { choiceJudge: judge })
    await handle(checksReq([moreover]))
    const again = await handle(checksReq([moreover]))
    expect(((await again.json()) as ChecksResponse).results[0].alsoCorrect).toEqual(['besides'])
    expect(judge.calls).toHaveLength(1)

    const withNew = await handle(checksReq([{ ...moreover, choices: ['however', 'also', 'unless'] }]))
    expect(((await withNew.json()) as ChecksResponse).results[0].alsoCorrect).toEqual(['also'])
    expect(judge.calls).toHaveLength(2)
    expect(judge.calls[1][0].candidates).toEqual(['also'])
  })

  it('ためた判定だけで済むなら、判定役が無くても返す', async () => {
    const { handle, db } = createTestApp({}, { choiceJudge: null })
    const insert = db.prepare('INSERT INTO fill_blank_checks (key, fits, created_at) VALUES (?, ?, 0)')
    insert.run(checkKey(moreover.text, 'moreover', 'however'), 0)
    insert.run(checkKey(moreover.text, 'moreover', 'besides'), 1)
    insert.run(checkKey(moreover.text, 'moreover', 'unless'), 0)
    const res = await handle(checksReq([moreover]))
    expect(res.status).toBe(200)
    expect(((await res.json()) as ChecksResponse).results[0].alsoCorrect).toEqual(['besides'])
  })

  it('判定していない組があって判定役が無ければ 503', async () => {
    const { handle } = createTestApp({}, { choiceJudge: null })
    expect((await handle(checksReq([moreover]))).status).toBe(503)
  })

  it('AI が失敗したら 502 で、判定はためない', async () => {
    const { handle, db, errors } = createTestApp({}, { choiceJudge: fakeJudge(new Error('boom')) })
    expect((await handle(checksReq([moreover]))).status).toBe(502)
    expect(db.prepare('SELECT COUNT(*) AS n FROM fill_blank_checks').get()).toEqual({ n: 0 })
    expect(errors.some((e) => e.includes('AI の呼び出しに失敗'))).toBe(true)
  })

  it('返事に無い選択肢は、ほかの正解にせず、ためもしない', async () => {
    const judge: ChoiceJudge = {
      async judge(questions) {
        return questions.map((q) => ({ id: q.id, verdicts: [{ word: 'besides', fits: true }] }))
      },
    }
    const { handle, db } = createTestApp({}, { choiceJudge: judge })
    const res = await handle(checksReq([moreover]))
    expect(((await res.json()) as ChecksResponse).results[0].alsoCorrect).toEqual(['besides'])
    expect(db.prepare('SELECT COUNT(*) AS n FROM fill_blank_checks').get()).toEqual({ n: 1 })
  })

  it('文章に見出し語が無い問題は判定せず、ほかの正解なしで返す', async () => {
    const judge = fakeJudge(['besides'])
    const { handle } = createTestApp({}, { choiceJudge: judge })
    const res = await handle(checksReq([{ ...moreover, text: 'It is a nice day today.' }, eitherOr]))
    expect(((await res.json()) as ChecksResponse).results).toEqual([
      { id: 'q1', alsoCorrect: [] },
      { id: 'q2', alsoCorrect: [] },
    ])
    expect(judge.calls[0].map((q) => q.id)).toEqual(['q2'])
  })

  it('正解と同じ語・重なった選択肢は判定しない', async () => {
    const judge = fakeJudge([])
    const { handle } = createTestApp({}, { choiceJudge: judge })
    await handle(checksReq([{ ...moreover, choices: ['Moreover', 'besides', 'besides'] }]))
    expect(judge.calls[0][0].candidates).toEqual(['besides'])
  })

  it('回数制限を超えたら 429', async () => {
    const { handle } = createTestApp({}, { choiceJudge: fakeJudge([]) })
    for (let i = 0; i < RATE_LIMIT; i++) {
      const res = await handle(checksReq([{ ...moreover, text: `${moreover.text} (${i})` }]))
      expect(res.status).toBe(200)
    }
    expect((await handle(checksReq([{ ...moreover, text: `${moreover.text} (x)` }]))).status).toBe(429)
  })
})
