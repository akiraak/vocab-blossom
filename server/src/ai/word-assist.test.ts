import { describe, expect, it } from 'vitest'
import { draftFromQuery } from '../admin/pages.ts'
import { TEST_ORIGIN, apiReq, createTestApp, req, testBundled } from '../test-helpers.ts'
import {
  type AiCandidate,
  MAX_INPUT_LENGTH,
  RATE_LIMIT,
  RateLimiter,
  type WordAssistResponse,
  type WordAssistant,
  WordAssistError,
  parseAiOutput,
  parseAssistInput,
  resolveCandidates,
} from './word-assist.ts'

function candidate(word: string, overrides: Partial<AiCandidate> = {}): AiCandidate {
  return {
    word,
    pos: 'noun',
    meaning: '意味',
    example: `This is ${word}.`,
    exampleJa: 'これは例です。',
    reason: 'exact',
    ...overrides,
  }
}

/** 呼ばれた入力を記録し、決まった候補を返す偽物 */
function fakeAssistant(result: AiCandidate[] | Error): WordAssistant & { calls: string[] } {
  const calls: string[] = []
  return {
    calls,
    async suggest(text) {
      calls.push(text)
      if (result instanceof Error) throw result
      return result
    },
  }
}

function assistReq(body: unknown): Request {
  return apiReq('/api/word-assist', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

describe('parseAssistInput', () => {
  it('前後の空白を落とし、続く空白を 1 つにする', () => {
    expect(parseAssistInput({ text: '  take   care of ' })).toBe('take care of')
  })

  it('空・文字列でない・長すぎるのは不正', () => {
    for (const body of [null, [], {}, { text: 1 }, { text: '   ' }, { text: 'a'.repeat(MAX_INPUT_LENGTH + 1) }]) {
      expect(() => parseAssistInput(body), JSON.stringify(body)).toThrow()
    }
    expect(parseAssistInput({ text: 'あ'.repeat(MAX_INPUT_LENGTH) })).toHaveLength(MAX_INPUT_LENGTH)
  })
})

describe('resolveCandidates', () => {
  const bundled = testBundled()

  it('同梱語に当たる候補には bundled を付け、無い語は null', () => {
    const [hit, miss] = resolveCandidates(
      [candidate('beautiful', { reason: 'typo' }), candidate('serendipity')],
      bundled,
    )
    const expected = bundled.findBySpelling('beautiful')!
    expect(hit.bundled).toEqual({
      id: expected.id,
      word: expected.word,
      meaning: expected.meaning,
      pos: expected.pos,
      level: expected.level,
    })
    expect(hit.reason).toBe('typo')
    expect(miss.bundled).toBeNull()
  })

  it('大小文字・空白の違いも同じ綴りとみなし、重複は最初の 1 つだけ残す', () => {
    const result = resolveCandidates([candidate(' Beautiful '), candidate('beautiful'), candidate('pretty')], bundled)
    expect(result.map((c) => c.word)).toEqual(['Beautiful', 'pretty'])
    expect(result[0].bundled).not.toBeNull()
  })

  it('単語帳に無い語は品詞の違う候補を残し、同じ品詞の重複は落とす', () => {
    const result = resolveCandidates(
      [
        candidate('commute', { pos: 'verb', meaning: '通勤する' }),
        candidate('Commute', { pos: 'noun', meaning: '通勤' }),
        candidate('commute', { pos: 'verb', meaning: '通う' }),
      ],
      bundled,
    )
    expect(result.map((c) => [c.word, c.pos, c.meaning])).toEqual([
      ['commute', 'verb', '通勤する'],
      ['Commute', 'noun', '通勤'],
    ])
    expect(result.every((c) => c.bundled === null)).toBe(true)
  })

  it('単語帳にある語は、品詞が違っても案内は 1 つ', () => {
    const result = resolveCandidates(
      [candidate('beautiful', { pos: 'adjective' }), candidate('beautiful', { pos: 'adverb' })],
      bundled,
    )
    expect(result).toHaveLength(1)
    expect(result[0].bundled).not.toBeNull()
  })

  it('最大 5 件', () => {
    const result = resolveCandidates(['a1', 'b2', 'c3', 'd4', 'e5', 'f6'].map((w) => candidate(w)), bundled)
    expect(result).toHaveLength(5)
  })
})

describe('parseAiOutput', () => {
  it('形の合わない候補は捨て、使える候補が無ければ WordAssistError', () => {
    const result = parseAiOutput({
      candidates: [
        candidate('ok'),
        { ...candidate('bad-pos'), pos: 'verbish' },
        { ...candidate('bad-reason'), reason: 'guess' },
        { ...candidate(''), word: ' ' },
        { word: 'missing' },
      ],
    })
    expect(result.map((c) => c.word)).toEqual(['ok'])
    expect(() => parseAiOutput({ candidates: [] })).toThrow(WordAssistError)
    expect(() => parseAiOutput({})).toThrow(WordAssistError)
  })
})

describe('RateLimiter', () => {
  it('窓の中で上限を超えたら false、窓が過ぎればまた使える', () => {
    let now = 0
    const limiter = new RateLimiter(2, 1000, () => now)
    expect(limiter.take()).toBe(true)
    expect(limiter.take()).toBe(true)
    expect(limiter.take()).toBe(false)
    now = 1000
    expect(limiter.take()).toBe(true)
  })
})

describe('POST /api/word-assist', () => {
  it('Bearer が無ければ 401', async () => {
    const { handle } = createTestApp({}, { assistant: fakeAssistant([]) })
    const res = await handle(req('/api/word-assist', { method: 'POST', body: '{"text":"a"}' }))
    expect(res.status).toBe(401)
  })

  it('AI が使えない（キー未設定）なら 503', async () => {
    const { handle } = createTestApp()
    const res = await handle(assistReq({ text: 'beautifull' }))
    expect(res.status).toBe(503)
    expect(await res.json()).toEqual({ error: 'ai-unavailable' })
  })

  it('入力が不正なら 400 で、AI は呼ばない', async () => {
    const assistant = fakeAssistant([candidate('x')])
    const { handle } = createTestApp({}, { assistant })
    expect((await handle(assistReq('not json'))).status).toBe(400)
    expect((await handle(assistReq({ text: '' }))).status).toBe(400)
    expect(assistant.calls).toEqual([])
  })

  it('候補を同梱語と照合して返す', async () => {
    const assistant = fakeAssistant([
      candidate('beautiful', { reason: 'typo', pos: 'adjective', meaning: '美しい' }),
      candidate('beautifully', { reason: 'typo', pos: 'adverb' }),
    ])
    const { handle } = createTestApp({}, { assistant })
    const res = await handle(assistReq({ text: ' beautifull ' }))
    expect(res.status).toBe(200)
    const body = (await res.json()) as WordAssistResponse
    expect(assistant.calls).toEqual(['beautifull'])
    expect(body.text).toBe('beautifull')
    expect(body.candidates).toHaveLength(2)
    expect(body.candidates[0]).toMatchObject({ word: 'beautiful', reason: 'typo', meaning: '美しい' })
    expect(body.candidates[0].bundled?.id).toBe(testBundled().findBySpelling('beautiful')!.id)
    expect(body.candidates[1].bundled).toBeNull()
  })

  it('AI が失敗したら 502 にしてログに出す', async () => {
    const { handle, errors } = createTestApp({}, { assistant: fakeAssistant(new WordAssistError('boom')) })
    const res = await handle(assistReq({ text: 'beautifull' }))
    expect(res.status).toBe(502)
    expect(await res.json()).toEqual({ error: 'ai-failed' })
    expect(errors.some((e) => e.includes('word-assist'))).toBe(true)
  })

  it('回数制限を超えたら 429（AI は呼ばない）', async () => {
    const assistant = fakeAssistant([candidate('x')])
    const { handle } = createTestApp({}, { assistant })
    for (let i = 0; i < RATE_LIMIT; i++) {
      expect((await handle(assistReq({ text: 'x' }))).status).toBe(200)
    }
    const res = await handle(assistReq({ text: 'x' }))
    expect(res.status).toBe(429)
    expect(assistant.calls).toHaveLength(RATE_LIMIT)
  })
})

describe('POST /admin/word-assist', () => {
  function adminAssist(origin: string | null): Request {
    const headers: Record<string, string> = { 'content-type': 'application/json' }
    if (origin) headers.origin = origin
    return req('/admin/word-assist', { method: 'POST', headers, body: JSON.stringify({ text: 'went' }) })
  }

  it('自分のホストからなら候補を返す', async () => {
    const { handle } = createTestApp({}, { assistant: fakeAssistant([candidate('go', { reason: 'inflection' })]) })
    const res = await handle(adminAssist(TEST_ORIGIN))
    expect(res.status).toBe(200)
    expect(((await res.json()) as WordAssistResponse).candidates[0].bundled).not.toBeNull()
  })

  it('Origin が違えば 403、ADMIN_ENABLED が無ければ 404', async () => {
    const assistant = fakeAssistant([candidate('go')])
    expect((await createTestApp({}, { assistant }).handle(adminAssist('https://evil.test'))).status).toBe(403)
    expect(
      (await createTestApp({ adminEnabled: false }, { assistant }).handle(adminAssist(TEST_ORIGIN))).status,
    ).toBe(404)
  })
})

describe('管理画面の「AI で調べる」', () => {
  async function groupPage(handle: (r: Request) => Promise<Response>, query = '') {
    const created = await handle(
      req('/admin/groups', {
        method: 'POST',
        headers: { origin: TEST_ORIGIN, 'content-type': 'application/x-www-form-urlencoded' },
        body: 'name=test',
      }),
    )
    const path = created.headers.get('location') ?? ''
    const res = await handle(req(`${path}${query ? `?q=${encodeURIComponent(query)}` : ''}`))
    return { path, body: await res.text() }
  }

  it('AI が使えるときだけ、自作語のフォームに出す（グループでは同梱語の追加先つき）', async () => {
    // 共通の JS にも data-assist の文字列があるので、欄そのもの（class="assist"）で見分ける
    const box = 'class="assist" data-assist'
    const withAi = createTestApp({}, { assistant: fakeAssistant([]) })
    const { path, body } = await groupPage(withAi.handle, 'zzqqxx')
    expect(body).toContain(box)
    expect(body).toContain(`data-add-action="${path}/words"`)
    expect(await (await withAi.handle(req('/admin/custom-words'))).text()).toContain(box)

    const withoutAi = createTestApp()
    expect((await groupPage(withoutAi.handle, 'zzqqxx')).body).not.toContain(box)
    expect(await (await withoutAi.handle(req('/admin/custom-words'))).text()).not.toContain(box)
  })

  it('グループ詳細では、検索結果が 0 件のときだけ開いたらすぐ AI で調べる', async () => {
    const { handle } = createTestApp({}, { assistant: fakeAssistant([]) })
    // 共通の JS にも data-assist-autorun の文字列があるので、欄の属性の並びで見分ける
    const autorun = /data-assist-autorun\s+data-pos-labels/
    expect((await groupPage(handle, 'zzqqxx')).body).toMatch(autorun)
    const found = await groupPage(handle, 'get up')
    expect(found.body).toContain('class="assist" data-assist')
    expect(found.body).not.toMatch(autorun)
    // 検索語が無ければ AI の欄も作成のフォームも出さない
    const empty = await groupPage(handle)
    expect(empty.body).not.toContain('class="assist" data-assist')
    expect(empty.body).not.toContain('/custom-words" class="stack"')
  })

  it('検索で見つからなかった語をフォームに入れておく', async () => {
    const { handle } = createTestApp({}, { assistant: fakeAssistant([]) })
    const { body } = await groupPage(handle, 'zzqqxx')
    expect(body).toContain('name="word" value="zzqqxx"')
  })
})

describe('draftFromQuery', () => {
  it('英語は英語欄（空白があれば熟語）、日本語は意味欄へ', () => {
    expect(draftFromQuery(' beautifull ')).toMatchObject({ word: 'beautifull', meaning: '', pos: 'noun' })
    expect(draftFromQuery('take care')).toMatchObject({ word: 'take care', pos: 'phrase' })
    expect(draftFromQuery('世話をする')).toMatchObject({ word: '', meaning: '世話をする' })
    expect(draftFromQuery('  ')).toMatchObject({ word: '', meaning: '' })
  })
})
