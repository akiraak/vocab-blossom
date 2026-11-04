import { describe, expect, it } from 'vitest'
import { RATE_LIMIT } from './word-assist.ts'
import { apiReq, createTestApp, req } from '../test-helpers.ts'
import { countHeadword } from '../words/inflect.ts'
import { parsePassagesOutput, passagesUserMessage } from './claude-passages.ts'
import {
  MAX_WORDS_PER_REQUEST,
  type Passage,
  type PassageWord,
  type PassageWriter,
  type PassagesResponse,
  PassagesInputError,
  parsePassagesInput,
  passageKey,
  passageProblems,
  sentenceCount,
  wordCount,
} from './passages.ts'

const shower: PassageWord = {
  id: 'ph-0004',
  word: 'take a shower',
  pos: 'phrase',
  meaning: 'シャワーを浴びる',
  example: 'He takes a shower every morning.',
}

const showerPassages: Passage[] = [
  {
    text: 'I ran ten kilometers today, so my body was hot and dirty. When I got home, I took a shower right away.',
    ja: '今日は 10 キロ走ったので、体が熱くて汚れていた。家に帰るとすぐにシャワーを浴びた。',
  },
  {
    text: 'There is no hot water this morning. My sister is angry because she cannot take a shower before school.',
    ja: '今朝はお湯が出ない。姉は学校の前にシャワーを浴びられないので怒っている。',
  },
  {
    text: 'After the soccer game, all the players went to the locker room. They wanted to take a shower and wash off the mud.',
    ja: 'サッカーの試合のあと、選手はみんなロッカールームへ行った。シャワーを浴びて泥を落としたかった。',
  },
]

const lend: PassageWord = { id: 'a2-0620', word: 'lend', pos: 'verb', meaning: '貸す', example: 'Can you lend me your umbrella?' }
const lendPassages: Passage[] = [
  {
    text: "Tom didn't have any money for lunch. I had extra, so I lent him 500 yen. He will pay me back tomorrow.",
    ja: 'トムは昼食のお金を持っていなかった。私は余分に持っていたので、彼に500円を貸した。彼は明日返してくれる。',
  },
  {
    text: "My sister has many books. She often lends them to her friends, but sometimes they don't give them back.",
    ja: '姉はたくさんの本を持っている。よく友達に貸すが、ときどき返してもらえない。',
  },
  {
    text: 'It started to rain, and Mika had no umbrella. I had two at school today, so I lent one to her.',
    ja: '雨が降り始めたが、ミカは傘を持っていなかった。今日は学校に 2 本あったので、1 本を彼女に貸した。',
  },
]

/** 呼ばれた語を記録し、決めた順に返事を返す偽物（足りなくなったら最後の返事を繰り返す） */
function fakeWriter(...responses: (Record<string, Passage[]> | Error)[]): PassageWriter & { calls: string[][] } {
  const calls: string[][] = []
  return {
    calls,
    async write(words) {
      calls.push(words.map((w) => w.id))
      const response = responses[Math.min(calls.length - 1, responses.length - 1)]
      if (response instanceof Error) throw response
      return words.flatMap((w) => (response[w.id] ? [{ id: w.id, passages: response[w.id] }] : []))
    },
  }
}

function passagesReq(words: unknown): Request {
  return apiReq('/api/passages', { method: 'POST', body: JSON.stringify({ words }) })
}

describe('穴埋めの文章の検証', () => {
  it('見出し語の数を活用形・熟語も含めて数える', () => {
    expect(countHeadword('He takes a shower. Then he took a shower again.', 'take a shower')).toBe(2)
    expect(countHeadword('She went home and goes to bed.', 'go')).toBe(2)
    expect(countHeadword('I like apples.', 'banana')).toBe(0)
  })

  it('語数と文の数を数える', () => {
    expect(wordCount('  I like  apples. ')).toBe(3)
    expect(sentenceCount('I was tired. Was I sleepy? Yes!')).toBe(3)
    expect(sentenceCount('No end mark')).toBe(1)
  })

  it('3 パターンとも条件を満たせば問題なし', () => {
    expect(passageProblems(shower, showerPassages)).toEqual([])
    expect(passageProblems(lend, lendPassages)).toEqual([])
  })

  it('数・見出し語の回数・語数・文の数・例文の流用・和訳の句点・重複を見つける', () => {
    const [a, b, c] = showerPassages
    expect(passageProblems(shower, [a, b])[0]).toContain('パターンが 2 個')
    const twice = { ...a, text: `${a.text} Then she took a shower too.` }
    expect(passageProblems(shower, [twice, b, c])).toEqual([expect.stringContaining('見出し語が 2 回')])
    const short = { text: 'I take a shower.', ja: 'シャワーを浴びる。' }
    expect(passageProblems(shower, [short, b, c]).join()).toMatch(/4 語.*1 文/)
    const reused = { ...a, text: `It was very hot in our small town all week. ${shower.example}` }
    expect(passageProblems(shower, [reused, b, c])).toEqual([expect.stringContaining('例文をそのまま')])
    expect(passageProblems(shower, [{ ...a, ja: 'シャワーを浴びた' }, b, c])).toEqual([
      expect.stringContaining('句点'),
    ])
    expect(passageProblems(shower, [a, a, c])).toEqual([expect.stringContaining('同じ文章')])
  })

  it('例文が空のマイ単語でも検証できる', () => {
    expect(passageProblems({ ...shower, example: '' }, showerPassages)).toEqual([])
  })
})

describe('入力と鍵', () => {
  it('語を読み、前後の空白を落とす', () => {
    expect(parsePassagesInput({ words: [{ ...shower, word: ' take a shower ' }] })).toEqual([shower])
    expect(parsePassagesInput({ words: [{ ...shower, example: '' }] })[0].example).toBe('')
  })

  it('形が違う・多すぎる・品詞が不正なら弾く', () => {
    const tooMany = Array.from({ length: MAX_WORDS_PER_REQUEST + 1 }, (_, i) => ({ ...shower, id: `x${i}` }))
    for (const body of [
      null,
      [],
      { words: [] },
      { words: tooMany },
      { words: [{ ...shower, pos: 'verbish' }] },
      { words: [{ ...shower, meaning: ' ' }] },
      { words: [{ ...shower, word: 1 }] },
    ]) {
      expect(() => parsePassagesInput(body), JSON.stringify(body)).toThrow(PassagesInputError)
    }
  })

  it('鍵は綴り（大小文字は区別しない）・品詞・意味。意味が変われば別の鍵', () => {
    expect(passageKey({ ...shower, word: 'Take A Shower' })).toBe(passageKey(shower))
    expect(passageKey({ ...shower, meaning: 'シャワーする' })).not.toBe(passageKey(shower))
    expect(passageKey({ ...shower, pos: 'verb' })).not.toBe(passageKey(shower))
  })
})

describe('AI への入力と返事', () => {
  it('1 語 1 行の JSON で送る', () => {
    const lines = passagesUserMessage([shower, lend]).split('\n')
    expect(lines).toHaveLength(2)
    expect(JSON.parse(lines[0])).toEqual({
      id: 'ph-0004',
      word: 'take a shower',
      pos: 'phrase',
      meaning: 'シャワーを浴びる',
      example: shower.example,
    })
  })

  it('返事の形を確かめ、壊れた項目は捨てる', () => {
    expect(
      parsePassagesOutput({
        items: [
          { id: 'a', passages: [{ text: 't', ja: 'j', extra: 1 }, { text: 2 }] },
          { id: 3, passages: [] },
          null,
        ],
      }),
    ).toEqual([{ id: 'a', passages: [{ text: 't', ja: 'j' }] }])
    expect(() => parsePassagesOutput({})).toThrow()
  })
})

describe('POST /api/passages', () => {
  it('Bearer が無ければ 401', async () => {
    const { handle } = createTestApp({}, { passageWriter: fakeWriter({}) })
    const res = await handle(req('/api/passages', { method: 'POST', body: JSON.stringify({ words: [shower] }) }))
    expect(res.status).toBe(401)
  })

  it('AI で作り、検証を通ったものをためて返す。2 回目は AI を呼ばない', async () => {
    const writer = fakeWriter({ 'ph-0004': showerPassages, 'a2-0620': lendPassages })
    const { handle } = createTestApp({}, { passageWriter: writer })

    const first = await handle(passagesReq([shower, lend]))
    expect(first.status).toBe(200)
    const body = (await first.json()) as PassagesResponse
    expect(body.results.map((r) => [r.id, r.passages.length])).toEqual([
      ['ph-0004', 3],
      ['a2-0620', 3],
    ])
    expect(writer.calls).toEqual([['ph-0004', 'a2-0620']])

    // 別の端末（別の id）でも、同じ綴り・品詞・意味ならためた文章を返す
    const second = await handle(passagesReq([{ ...shower, id: 'custom-1', word: 'Take a shower' }]))
    const again = (await second.json()) as PassagesResponse
    expect(again.results[0]).toEqual({ id: 'custom-1', passages: showerPassages })
    expect(writer.calls).toHaveLength(1)
  })

  it('検証に通らなかった語だけ 1 回作り直し、それでも駄目なら空で返す', async () => {
    const bad = [showerPassages[0], showerPassages[1]]
    const writer = fakeWriter({ 'ph-0004': bad, 'a2-0620': lendPassages }, { 'ph-0004': bad })
    const { handle, db } = createTestApp({}, { passageWriter: writer })

    const res = await handle(passagesReq([shower, lend]))
    const body = (await res.json()) as PassagesResponse
    expect(writer.calls).toEqual([['ph-0004', 'a2-0620'], ['ph-0004']])
    expect(body.results).toEqual([
      { id: 'ph-0004', passages: [] },
      { id: 'a2-0620', passages: lendPassages },
    ])
    expect(db.prepare('SELECT count(*) AS n FROM word_passages').get()).toEqual({ n: 1 })
  })

  it('作り直しで通れば、その文章を返す', async () => {
    const writer = fakeWriter({ 'ph-0004': showerPassages.slice(0, 1) }, { 'ph-0004': showerPassages })
    const { handle } = createTestApp({}, { passageWriter: writer })
    const body = (await (await handle(passagesReq([shower]))).json()) as PassagesResponse
    expect(body.results[0].passages).toEqual(showerPassages)
  })

  it('AI が失敗したら 502', async () => {
    const { handle, errors } = createTestApp({}, { passageWriter: fakeWriter(new Error('boom')) })
    const res = await handle(passagesReq([shower]))
    expect(res.status).toBe(502)
    expect(errors.join()).toContain('[passages]')
  })

  it('AI が無いとき、ためた文章だけなら返し、作る必要があれば 503', async () => {
    const withAi = createTestApp({}, { passageWriter: fakeWriter({ 'ph-0004': showerPassages }) })
    await withAi.handle(passagesReq([shower]))

    const res = await withAi.handle(passagesReq([shower]))
    expect(res.status).toBe(200)

    const { handle } = createTestApp()
    expect((await handle(passagesReq([shower]))).status).toBe(503)
  })

  it('入力が不正なら 400', async () => {
    const { handle } = createTestApp({}, { passageWriter: fakeWriter({}) })
    expect((await handle(passagesReq([{ ...shower, pos: 'x' }]))).status).toBe(400)
    const broken = await handle(apiReq('/api/passages', { method: 'POST', body: '{' }))
    expect(broken.status).toBe(400)
  })

  it('AI を呼んだ回数が枠を超えたら 429', async () => {
    const writer = fakeWriter({})
    const { handle } = createTestApp({}, { passageWriter: writer, now: () => 0 })
    // 文章が返らない語は 1 回のリクエストで 2 回（作り直し）AI を呼ぶ
    for (let i = 0; i < RATE_LIMIT / 2; i++) {
      expect((await handle(passagesReq([{ ...shower, id: `w${i}` }]))).status).toBe(200)
    }
    expect((await handle(passagesReq([shower]))).status).toBe(429)
  })
})
