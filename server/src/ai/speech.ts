import { createHash } from 'node:crypto'
import { InvalidJsonError, PayloadTooLargeError, readJson } from '../http/body.ts'
import { json } from '../http/responses.ts'
import type { Handler } from '../http/router.ts'
import type { RateLimiter } from './word-assist.ts'
import { ModelInputError, TTS_MODELS, type TtsModel, parseModel } from './models.ts'

// グループの読み上げの声（POST /api/speech）。1 文を Gemini TTS で読ませて WAV で返す。
// 声（キャラ）と文の種類ごとのスタイルはサーバーが持つ（アプリの更新なしで直せる）。
// 決めた値は Phase 1 の試聴によるもの。docs/plans/archive/read-aloud-gemini-voice.md

export const SPEECH_BODY_LIMIT = 4 * 1024
export const MAX_SPEECH_TEXT_LENGTH = 300
/** 1 語で 2 人 × 4 文 = 8 回呼ぶ。10 分で 75 語ぶん（読み上げは 1 語 15 秒ほどなので、先読みを入れても足りる） */
export const SPEECH_RATE_LIMIT = 600

export const SPEAKERS = ['chobi', 'naruko'] as const
export type Speaker = (typeof SPEAKERS)[number]

/** word: 見出し語、example: 英語の例文、japanese: 意味・例文の和訳 */
export const SPEECH_KINDS = ['word', 'example', 'japanese'] as const
export type SpeechKind = (typeof SPEECH_KINDS)[number]

type Voice = { voice: string; styles: Record<SpeechKind, string> }

/** esl-speaking-coach の Chobi（Leda）/ Naruko（Aoede）。スタイルは読み上げ用に短くしたもの */
export const VOICES: Record<Speaker, Voice> = {
  chobi: {
    voice: 'Leda',
    styles: {
      word: 'warm and clear, like a friendly teacher, speaking slowly',
      example: 'warm and friendly, like a teacher reading to a beginner, calm natural pace',
      japanese: 'warm and friendly, like a teacher explaining, calm natural pace',
    },
  },
  naruko: {
    voice: 'Aoede',
    styles: {
      word: 'bright and cheerful, clear, speaking slowly',
      example: 'bright and cheerful, like a classmate reading to a friend, calm natural pace',
      japanese: 'bright and cheerful, like a classmate explaining to a friend, calm natural pace',
    },
  },
}

/** model を省いたら env（無ければ既定）のモデル */
export type SpeechInput = { text: string; speaker: Speaker; kind: SpeechKind; model?: TtsModel }

/** PCM16（リトルエンディアン・mono） */
export type SynthesizedSpeech = { pcm: Buffer; sampleRate: number }

/** TTS の呼び出し。本番は gemini-tts.ts、テストは偽物に差し替える */
export type SpeechSynthesizer = {
  /** model を省いたときのモデル */
  model: string
  synthesize: (request: { voice: string; style: string; text: string; model?: TtsModel }) => Promise<SynthesizedSpeech>
}

export class SpeechInputError extends Error {}

export function parseSpeechInput(body: unknown): SpeechInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new SpeechInputError('JSON のオブジェクトで送ってください')
  }
  const { text, speaker, kind } = body as Record<string, unknown>
  if (typeof text !== 'string' || text.trim() === '') throw new SpeechInputError('text が空です')
  if (text.trim().length > MAX_SPEECH_TEXT_LENGTH) throw new SpeechInputError('text が長すぎます')
  if (typeof speaker !== 'string' || !(SPEAKERS as readonly string[]).includes(speaker)) {
    throw new SpeechInputError('speaker が不正です')
  }
  if (typeof kind !== 'string' || !(SPEECH_KINDS as readonly string[]).includes(kind)) {
    throw new SpeechInputError('kind が不正です')
  }
  const model = parseModel(body, TTS_MODELS)
  return { text: text.trim(), speaker: speaker as Speaker, kind: kind as SpeechKind, ...(model ? { model } : {}) }
}

/**
 * 同じ文でも、モデル・声・スタイルが変われば別の音声になる。その組み合わせの版（短いハッシュ）。
 * iOS は端末に残す音声の鍵に使い、版が変われば作り直す
 */
export function speechVersion(model: string, speaker: Speaker, kind: SpeechKind): string {
  const { voice, styles } = VOICES[speaker]
  return createHash('sha256').update([model, voice, styles[kind]].join('\n')).digest('hex').slice(0, 12)
}

/** 44 バイトのヘッダを付けた WAV（PCM16・mono） */
export function pcmToWav(pcm: Buffer, sampleRate: number): Buffer {
  const header = Buffer.alloc(44)
  header.write('RIFF', 0, 'ascii')
  header.writeUInt32LE(36 + pcm.length, 4)
  header.write('WAVE', 8, 'ascii')
  header.write('fmt ', 12, 'ascii')
  header.writeUInt32LE(16, 16)
  header.writeUInt16LE(1, 20) // PCM
  header.writeUInt16LE(1, 22) // mono
  header.writeUInt32LE(sampleRate, 24)
  header.writeUInt32LE(sampleRate * 2, 28)
  header.writeUInt16LE(2, 32)
  header.writeUInt16LE(16, 34)
  header.write('data', 36, 'ascii')
  header.writeUInt32LE(pcm.length, 40)
  return Buffer.concat([header, pcm])
}

export type SpeechDeps = {
  /** null ならキー未設定（503。iOS は内蔵 TTS で読む） */
  synthesizer: SpeechSynthesizer | null
  limiter: RateLimiter
  logError: (message: string, error?: unknown) => void
}

export function speechHandler({ synthesizer, limiter, logError }: SpeechDeps): Handler {
  return async (request) => {
    let input: SpeechInput
    try {
      input = parseSpeechInput(await readJson(request, SPEECH_BODY_LIMIT))
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return json({ error: 'payload too large' }, 413)
      if (error instanceof InvalidJsonError || error instanceof SpeechInputError || error instanceof ModelInputError) {
        return json({ error: error.message }, 400)
      }
      throw error
    }

    if (!synthesizer) return json({ error: 'tts-unavailable' }, 503)
    if (!limiter.take()) return json({ error: 'rate-limited' }, 429, { 'retry-after': '60' })

    const { voice, styles } = VOICES[input.speaker]
    let speech: SynthesizedSpeech
    try {
      speech = await synthesizer.synthesize({ voice, style: styles[input.kind], text: input.text, model: input.model })
    } catch (error) {
      logError('[speech] TTS の呼び出しに失敗', error)
      const status = (error as { status?: unknown })?.status
      if (status === 429) return json({ error: 'rate-limited' }, 429, { 'retry-after': '30' })
      return json({ error: 'tts-failed' }, 502)
    }

    return new Response(new Uint8Array(pcmToWav(speech.pcm, speech.sampleRate)), {
      status: 200,
      headers: {
        'content-type': 'audio/wav',
        'x-speech-version': speechVersion(input.model ?? synthesizer.model, input.speaker, input.kind),
      },
    })
  }
}
