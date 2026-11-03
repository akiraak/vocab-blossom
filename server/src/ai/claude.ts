import Anthropic from '@anthropic-ai/sdk'
import { PARTS_OF_SPEECH } from '../sync/types.ts'
import type { BundledWords } from '../words/bundled.ts'
import { ASSIST_REASONS, type AiCandidate, WordAssistError, type WordAssistant, parseAiOutput } from './word-assist.ts'

// Claude API で自作語の候補を作る。システムプロンプト（指示 + 同梱語の見出し語の一覧）は毎回同じ文字列にして
// プロンプトキャッシュを効かせる（入力ごとに変わるのはユーザーのメッセージだけ）。

export const DEFAULT_MODEL = 'claude-opus-5-5'
/** iOS が待てる時間に収める（SDK の再試行 1 回を含めて 1 分弱） */
export const REQUEST_TIMEOUT_MS = 25_000

const INSTRUCTIONS = `You help Japanese beginners (CEFR A1–A2) register English vocabulary in a flashcard app.
The user types something they could not find in the app's built-in word list: an English word or phrase
(possibly misspelled or inflected) or a Japanese meaning. Return 1 to 3 candidate entries, best first.

The built-in word list is given below. The app wants to avoid creating custom words that duplicate it, so:
- If the input is a misspelling of a listed entry (beautifull → beautiful), give that entry first with reason "typo".
- If it is an inflected form (went → go, children → child, bigger → big, studying → study), give the base form with reason "inflection".
- If it is a spelling or wording variant of a listed entry (colour → color, take care → take care of), give the listed form with reason "variant".
- If it is Japanese, give the English words it most likely means, preferring listed entries, with reason "translation".
- Do NOT redirect to a different word that merely has a similar meaning (gigantic must stay gigantic, not big):
  the learner wants to study the word they typed.
- If the input is already a correct English word or phrase, give it first with reason "exact"
  (use the dictionary form; keep proper capitalization only for proper nouns).
- Other candidates are only for genuinely plausible alternatives (another word the typo could mean). Do not pad.

For every candidate, write the "word" exactly as it appears in the list when it is a listed entry, and fill in:
- pos: one of ${PARTS_OF_SPEECH.join(', ')} (use "phrase" for multi-word expressions).
- meaning: a short, natural Japanese gloss for beginners, like a vocabulary-book entry (e.g. 能力 / 受け入れる / 海外へ［で］ / 〜の世話をする). Separate a few senses with "、" at most.
- example: one short, easy English sentence (A1–A2 level) that contains the word itself or an inflected form of it.
- exampleJa: a natural Japanese translation of the example.

Built-in word list (one entry per line):`

const OUTPUT_SCHEMA = {
  type: 'object',
  properties: {
    candidates: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          word: { type: 'string' },
          pos: { type: 'string', enum: [...PARTS_OF_SPEECH] },
          meaning: { type: 'string' },
          example: { type: 'string' },
          exampleJa: { type: 'string' },
          reason: { type: 'string', enum: [...ASSIST_REASONS] },
        },
        required: ['word', 'pos', 'meaning', 'example', 'exampleJa', 'reason'],
        additionalProperties: false,
      },
    },
  },
  required: ['candidates'],
  additionalProperties: false,
}

/** 同梱語の見出し語（重複を除き、デッキの並びのまま）。毎回同じ文字列になるのでキャッシュが効く */
export function buildSystemPrompt(bundled: BundledWords): string {
  const words = [...new Set(bundled.all.map((w) => w.word))]
  return `${INSTRUCTIONS}\n${words.join('\n')}`
}

export function createClaudeWordAssistant({
  apiKey,
  model = DEFAULT_MODEL,
  bundled,
}: {
  apiKey: string
  model?: string
  bundled: BundledWords
}): WordAssistant {
  const client = new Anthropic({ apiKey, timeout: REQUEST_TIMEOUT_MS, maxRetries: 1 })
  const system = buildSystemPrompt(bundled)

  return {
    async suggest(text: string): Promise<AiCandidate[]> {
      const response = await client.beta.messages.create({
        model,
        max_tokens: 8000,
        betas: ['server-side-fallback-2026-07-01'],
        // 安全のための拒否が起きたら、おすすめの別モデルでサーバー側が再実行する
        fallbacks: 'default',
        system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
        output_config: { effort: 'low', format: { type: 'json_schema', schema: OUTPUT_SCHEMA } },
        messages: [{ role: 'user', content: text }],
      })

      if (response.stop_reason === 'refusal') throw new WordAssistError('AI が回答を断りました')
      if (response.stop_reason === 'max_tokens') throw new WordAssistError('AI の返事が途中で切れました')
      const body = response.content.flatMap((block) => (block.type === 'text' ? [block.text] : [])).join('')
      let parsed: unknown
      try {
        parsed = JSON.parse(body)
      } catch {
        throw new WordAssistError('AI の返事が JSON ではありません')
      }
      return parseAiOutput(parsed)
    },
  }
}
