import type { SpeechSynthesizer, SynthesizedSpeech } from './speech.ts'

// Gemini TTS で 1 文の音声を作る（Interactions API）。
// スタイルは本文に混ぜず speech_metadata.style で渡す（3.8 は本文の頭に前置文を書くとそのまま読まれる）。
// 呼び方は試聴スクリプト（scripts/tts-audition.mjs）で確かめたもの。docs/plans/archive/read-aloud-gemini-voice.md

export const DEFAULT_TTS_MODEL = 'gemini-3.8-flash-tts'
export const INTERACTIONS_URL = 'https://generativelanguage.googleapis.com/v1beta/interactions'
/** 1 文の生成は 2〜3.5 秒（実測）。混んでいるときの余裕を見る */
export const TTS_TIMEOUT_MS = 30_000
const DEFAULT_SAMPLE_RATE = 24_000

export class GeminiTTSError extends Error {
  readonly status: number | undefined

  constructor(message: string, status?: number) {
    super(message)
    this.status = status
  }
}

export function interactionsRequestBody({
  model,
  voice,
  style,
  text,
}: {
  model: string
  voice: string
  style: string
  text: string
}): unknown {
  const content: Record<string, unknown> = { type: 'text', text }
  if (style !== '') content.annotations = [{ type: 'speech_metadata', style }]
  return {
    model,
    input: [{ type: 'user_input', content: [content] }],
    response_format: { type: 'audio', mime_type: 'audio/l16', sample_rate: DEFAULT_SAMPLE_RATE },
    generation_config: { speech_config: [{ voice }] },
  }
}

/** 返事から PCM16（リトルエンディアン・mono）を取り出す。WAV で返ってきたらヘッダを落とす */
export function parseInteractionsAudio(value: unknown): SynthesizedSpeech {
  const steps = (value as { steps?: unknown })?.steps
  const audio = (Array.isArray(steps) ? steps : [])
    .filter((step) => step?.type === 'model_output')
    .flatMap((step) => (Array.isArray(step.content) ? step.content : []))
    .filter((c) => c?.type === 'audio' && typeof c.data === 'string' && c.data !== '')
    .map((c) => ({ data: c.data as string, mimeType: String(c.mime_type ?? c.mimeType ?? '') }))
  if (audio.length === 0) throw new GeminiTTSError('音声が返らなかった')
  const rate = Number(/rate=(\d+)/.exec(audio[0].mimeType)?.[1] ?? DEFAULT_SAMPLE_RATE)
  const pcm = stripWavHeader(Buffer.concat(audio.map((a) => Buffer.from(a.data, 'base64'))))
  if (pcm.length === 0) throw new GeminiTTSError('音声が空だった')
  return { pcm, sampleRate: rate }
}

export function stripWavHeader(buffer: Buffer): Buffer {
  if (buffer.subarray(0, 4).toString('ascii') !== 'RIFF') return buffer
  const index = buffer.indexOf('data', 12, 'ascii')
  return index < 0 ? buffer.subarray(44) : buffer.subarray(index + 8)
}

export function createGeminiSpeechSynthesizer({
  apiKey,
  model = DEFAULT_TTS_MODEL,
  fetchImpl = fetch,
  timeoutMs = TTS_TIMEOUT_MS,
}: {
  apiKey: string
  model?: string
  fetchImpl?: typeof fetch
  timeoutMs?: number
}): SpeechSynthesizer {
  return {
    model,
    async synthesize({ voice, style, text, model: requestModel }) {
      const res = await fetchImpl(INTERACTIONS_URL, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify(interactionsRequestBody({ model: requestModel ?? model, voice, style, text })),
        signal: AbortSignal.timeout(timeoutMs),
      })
      const body: unknown = await res.json().catch(() => null)
      if (!res.ok) {
        const detail = JSON.stringify((body as { error?: unknown })?.error ?? body).slice(0, 300)
        throw new GeminiTTSError(`HTTP ${res.status}: ${detail}`, res.status)
      }
      return parseInteractionsAudio(body)
    },
  }
}
