import { describe, expect, it } from 'vitest'
import { apiReq, createTestApp, req } from '../test-helpers.ts'
import {
  GeminiTTSError,
  INTERACTIONS_URL,
  createGeminiSpeechSynthesizer,
  interactionsRequestBody,
  parseInteractionsAudio,
  stripWavHeader,
} from './gemini-tts.ts'
import {
  MAX_SPEECH_TEXT_LENGTH,
  SPEECH_RATE_LIMIT,
  SpeechInputError,
  type SpeechSynthesizer,
  VOICES,
  parseSpeechInput,
  pcmToWav,
  speechVersion,
} from './speech.ts'

const PCM = Buffer.from([1, 0, 2, 0, 3, 0, 4, 0])

type Call = { voice: string; style: string; text: string }

function fakeSynthesizer(
  behavior: (call: Call) => Promise<{ pcm: Buffer; sampleRate: number }> = async () => ({ pcm: PCM, sampleRate: 24000 }),
): SpeechSynthesizer & { calls: Call[] } {
  const calls: Call[] = []
  return {
    model: 'fake-tts',
    calls,
    async synthesize(call) {
      calls.push(call)
      return behavior(call)
    },
  }
}

function speechReq(body: unknown): Request {
  return apiReq('/api/speech', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

describe('parseSpeechInput', () => {
  it('前後の空白を落として受け取る', () => {
    expect(parseSpeechInput({ text: '  sit down ', speaker: 'chobi', kind: 'word' })).toEqual({
      text: 'sit down',
      speaker: 'chobi',
      kind: 'word',
    })
  })

  it('空・長すぎる文、知らない声・種類は受け付けない', () => {
    const ok = { text: 'Hello.', speaker: 'naruko', kind: 'example' }
    expect(() => parseSpeechInput(null)).toThrow(SpeechInputError)
    expect(() => parseSpeechInput([])).toThrow(SpeechInputError)
    expect(() => parseSpeechInput({ ...ok, text: '   ' })).toThrow(SpeechInputError)
    expect(() => parseSpeechInput({ ...ok, text: 1 })).toThrow(SpeechInputError)
    expect(() => parseSpeechInput({ ...ok, text: 'a'.repeat(MAX_SPEECH_TEXT_LENGTH + 1) })).toThrow(SpeechInputError)
    expect(() => parseSpeechInput({ ...ok, speaker: 'Leda' })).toThrow(SpeechInputError)
    expect(() => parseSpeechInput({ ...ok, kind: 'meaning' })).toThrow(SpeechInputError)
    expect(parseSpeechInput({ ...ok, text: 'a'.repeat(MAX_SPEECH_TEXT_LENGTH) }).text).toHaveLength(MAX_SPEECH_TEXT_LENGTH)
  })
})

describe('speechVersion', () => {
  it('モデル・声・スタイルが同じなら同じ、どれかが変われば別', () => {
    const base = speechVersion('m', 'chobi', 'word')
    expect(speechVersion('m', 'chobi', 'word')).toBe(base)
    expect(speechVersion('m2', 'chobi', 'word')).not.toBe(base)
    expect(speechVersion('m', 'naruko', 'word')).not.toBe(base)
    expect(speechVersion('m', 'chobi', 'example')).not.toBe(base)
    expect(base).toMatch(/^[0-9a-f]{12}$/)
  })
})

describe('pcmToWav / stripWavHeader', () => {
  it('44 バイトのヘッダを付け、外すと元に戻る', () => {
    const wav = pcmToWav(PCM, 24000)
    expect(wav.length).toBe(44 + PCM.length)
    expect(wav.subarray(0, 4).toString('ascii')).toBe('RIFF')
    expect(wav.subarray(8, 12).toString('ascii')).toBe('WAVE')
    expect(wav.readUInt32LE(24)).toBe(24000)
    expect(wav.readUInt16LE(34)).toBe(16)
    expect(wav.readUInt32LE(40)).toBe(PCM.length)
    expect(stripWavHeader(wav)).toEqual(PCM)
    expect(stripWavHeader(PCM)).toEqual(PCM)
  })
})

describe('Gemini TTS（Interactions API）', () => {
  it('スタイルは本文に混ぜず speech_metadata で渡す', () => {
    const body = interactionsRequestBody({ model: 'gemini-3.8-flash-tts', voice: 'Leda', style: 'speaking slowly', text: 'about' })
    expect(body).toEqual({
      model: 'gemini-3.8-flash-tts',
      input: [
        {
          type: 'user_input',
          content: [{ type: 'text', text: 'about', annotations: [{ type: 'speech_metadata', style: 'speaking slowly' }] }],
        },
      ],
      response_format: { type: 'audio', mime_type: 'audio/l16', sample_rate: 24000 },
      generation_config: { speech_config: [{ voice: 'Leda' }] },
    })
    const plain = interactionsRequestBody({ model: 'm', voice: 'Leda', style: '', text: 'about' }) as {
      input: { content: Record<string, unknown>[] }[]
    }
    expect(plain.input[0].content[0]).toEqual({ type: 'text', text: 'about' })
  })

  it('返事の音声（base64）をつなげて PCM にする', () => {
    const half = (b: Buffer) => b.toString('base64')
    const speech = parseInteractionsAudio({
      steps: [
        { type: 'thought', content: [] },
        {
          type: 'model_output',
          content: [
            { type: 'audio', mime_type: 'audio/l16;codec=pcm;rate=24000', data: half(PCM.subarray(0, 4)) },
            { type: 'audio', mime_type: 'audio/l16;codec=pcm;rate=24000', data: half(PCM.subarray(4)) },
          ],
        },
      ],
    })
    expect(speech).toEqual({ pcm: PCM, sampleRate: 24000 })
  })

  it('WAV で返ってきたらヘッダを落とし、音声が無ければ失敗にする', () => {
    const wav = pcmToWav(PCM, 16000)
    const speech = parseInteractionsAudio({
      steps: [{ type: 'model_output', content: [{ type: 'audio', mime_type: 'audio/wav; rate=16000', data: wav.toString('base64') }] }],
    })
    expect(speech).toEqual({ pcm: PCM, sampleRate: 16000 })
    expect(() => parseInteractionsAudio({ steps: [] })).toThrow(GeminiTTSError)
    expect(() => parseInteractionsAudio(null)).toThrow(GeminiTTSError)
  })

  it('キーをヘッダで送り、失敗は HTTP の状態つきで投げる', async () => {
    const seen: { url: string; init: RequestInit }[] = []
    const ok = createGeminiSpeechSynthesizer({
      apiKey: 'gm-key',
      fetchImpl: async (url, init) => {
        seen.push({ url: String(url), init: init! })
        return Response.json({ steps: [{ type: 'model_output', content: [{ type: 'audio', data: PCM.toString('base64') }] }] })
      },
    })
    expect(ok.model).toBe('gemini-3.8-flash-tts')
    expect(await ok.synthesize({ voice: 'Aoede', style: 's', text: 'Hi.' })).toEqual({ pcm: PCM, sampleRate: 24000 })
    expect(seen[0].url).toBe(INTERACTIONS_URL)
    expect(new Headers(seen[0].init.headers).get('x-goog-api-key')).toBe('gm-key')
    expect(String(seen[0].init.body)).not.toContain('gm-key')

    const failing = createGeminiSpeechSynthesizer({
      apiKey: 'gm-key',
      fetchImpl: async () => Response.json({ error: { message: 'quota' } }, { status: 429 }),
    })
    await expect(failing.synthesize({ voice: 'Aoede', style: 's', text: 'Hi.' })).rejects.toMatchObject({ status: 429 })
  })
})

describe('POST /api/speech', () => {
  it('声と種類に合うスタイルで読ませ、WAV と版を返す', async () => {
    const synthesizer = fakeSynthesizer()
    const { handle } = createTestApp({}, { speechSynthesizer: synthesizer })
    const res = await handle(speechReq({ text: 'Prices vary from shop to shop.', speaker: 'naruko', kind: 'example' }))
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toBe('audio/wav')
    expect(res.headers.get('x-speech-version')).toBe(speechVersion('fake-tts', 'naruko', 'example'))
    const wav = Buffer.from(await res.arrayBuffer())
    expect(wav).toEqual(pcmToWav(PCM, 24000))
    expect(synthesizer.calls).toEqual([
      { voice: 'Aoede', style: VOICES.naruko.styles.example, text: 'Prices vary from shop to shop.' },
    ])
  })

  it('日本語は japanese のスタイル、Chobi は Leda', async () => {
    const synthesizer = fakeSynthesizer()
    const { handle } = createTestApp({}, { speechSynthesizer: synthesizer })
    const res = await handle(speechReq({ text: '値段は店によって異なります。', speaker: 'chobi', kind: 'japanese' }))
    expect(res.status).toBe(200)
    expect(synthesizer.calls[0]).toMatchObject({ voice: 'Leda', style: VOICES.chobi.styles.japanese })
  })

  it('共有シークレットが無ければ 401', async () => {
    const { handle } = createTestApp({}, { speechSynthesizer: fakeSynthesizer() })
    const res = await handle(
      req('/api/speech', { method: 'POST', body: JSON.stringify({ text: 'a', speaker: 'chobi', kind: 'word' }) }),
    )
    expect(res.status).toBe(401)
  })

  it('入力が不正なら 400（TTS は呼ばない）', async () => {
    const synthesizer = fakeSynthesizer()
    const { handle } = createTestApp({}, { speechSynthesizer: synthesizer })
    expect((await handle(speechReq('{'))).status).toBe(400)
    expect((await handle(speechReq({ text: '', speaker: 'chobi', kind: 'word' }))).status).toBe(400)
    expect((await handle(speechReq({ text: 'a', speaker: 'kore', kind: 'word' }))).status).toBe(400)
    expect((await handle(speechReq({ text: 'a'.repeat(5000), speaker: 'chobi', kind: 'word' }))).status).toBe(413)
    expect(synthesizer.calls).toHaveLength(0)
  })

  it('キー未設定なら 503', async () => {
    const { handle } = createTestApp()
    const res = await handle(speechReq({ text: 'about', speaker: 'chobi', kind: 'word' }))
    expect(res.status).toBe(503)
    expect(await res.json()).toEqual({ error: 'tts-unavailable' })
  })

  it('TTS が失敗したら 502、上限なら 429。ログに残す', async () => {
    const failing = createTestApp({}, {
      speechSynthesizer: fakeSynthesizer(async () => {
        throw new GeminiTTSError('HTTP 500', 500)
      }),
    })
    const res = await failing.handle(speechReq({ text: 'about', speaker: 'chobi', kind: 'word' }))
    expect(res.status).toBe(502)
    expect(failing.errors.some((e) => e.includes('[speech]'))).toBe(true)

    const quota = createTestApp({}, {
      speechSynthesizer: fakeSynthesizer(async () => {
        throw new GeminiTTSError('HTTP 429', 429)
      }),
    })
    expect((await quota.handle(speechReq({ text: 'about', speaker: 'chobi', kind: 'word' }))).status).toBe(429)
  })

  it(`10 分で ${SPEECH_RATE_LIMIT} 回を超えたら 429`, async () => {
    const synthesizer = fakeSynthesizer()
    const { handle } = createTestApp({}, { speechSynthesizer: synthesizer, now: () => 1_000 })
    for (let i = 0; i < SPEECH_RATE_LIMIT; i++) {
      const res = await handle(speechReq({ text: `word ${i}`, speaker: 'chobi', kind: 'word' }))
      expect(res.status).toBe(200)
    }
    const res = await handle(speechReq({ text: 'one more', speaker: 'chobi', kind: 'word' }))
    expect(res.status).toBe(429)
    expect(res.headers.get('retry-after')).toBe('60')
    expect(synthesizer.calls).toHaveLength(SPEECH_RATE_LIMIT)
  })
})
