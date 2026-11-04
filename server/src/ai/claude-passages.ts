import Anthropic from '@anthropic-ai/sdk'
import { DEFAULT_MODEL } from './claude.ts'
import type { GeneratedPassages, PassageWord, PassageWriter } from './passages.ts'

// Claude API で穴埋め用の文章を作る。システムプロンプトは毎回同じ文字列にしてキャッシュを効かせる。
// 指示は 10 語で試して決めた（docs/plans/fill-blank-passages.md）。

/** iOS が待てる時間に収める（5 語で 3 パターンずつ。SDK の再試行 1 回を含めて 2 分弱） */
export const PASSAGES_TIMEOUT_MS = 55_000

export const PASSAGE_INSTRUCTIONS = `You write fill-in-the-blank reading passages for Japanese beginners (CEFR A1–A2) who are learning English vocabulary in a flashcard app.
In the quiz, the target word in your passage is replaced with a blank, and the learner chooses the missing word from four choices.
The three wrong choices are other words of the same part of speech, so the passage itself must make the target word clearly the best fit.

For each target word, write exactly 3 passages:
- Each passage is 2 or 3 short sentences, 18–40 words in total. Use only simple A1–A2 vocabulary and grammar.
- Use the target word exactly once, in the given meaning and part of speech. An inflected form is fine (takes, went, children, bigger).
  Do not use the word a second time, and avoid other words from the same family that would give the answer away (for "decide", do not write "decision").
- The other sentences must contain clues that point to the target word: the situation, the reason, the result, a short explanation, or a contrast.
  A learner who reads the whole passage should be able to guess the word even if they only half know it.
  Other words of the same part of speech should sound wrong in the blank.
- Make the three passages use different situations. Do not reuse the example sentence you are given.
- For a multi-word phrase, keep its words together in the usual order (only an object may come between a verb and its particle, as in "call you back").
- ja: a natural Japanese translation of the whole passage, ending with "。" (or "？" / "！").

Each input line is a JSON object with id, word, pos, meaning (Japanese) and example. Return one item per input word with the same id, in the same order.`

const OUTPUT_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          passages: {
            type: 'array',
            items: {
              type: 'object',
              properties: { text: { type: 'string' }, ja: { type: 'string' } },
              required: ['text', 'ja'],
              additionalProperties: false,
            },
          },
        },
        required: ['id', 'passages'],
        additionalProperties: false,
      },
    },
  },
  required: ['items'],
  additionalProperties: false,
}

export function passagesUserMessage(words: PassageWord[]): string {
  return words
    .map((w) => JSON.stringify({ id: w.id, word: w.word, pos: w.pos, meaning: w.meaning, example: w.example }))
    .join('\n')
}

/** AI の返事（JSON）を形だけ確かめる。中身の検証は passages.ts の passageProblems */
export function parsePassagesOutput(value: unknown): GeneratedPassages[] {
  const items = (value as { items?: unknown })?.items
  if (!Array.isArray(items)) throw new Error('items がありません')
  return items.flatMap((item) => {
    const { id, passages } = (item ?? {}) as { id?: unknown; passages?: unknown }
    if (typeof id !== 'string' || !Array.isArray(passages)) return []
    const valid = passages.filter(
      (p): p is { text: string; ja: string } =>
        typeof p?.text === 'string' && typeof p?.ja === 'string',
    )
    return [{ id, passages: valid.map(({ text, ja }) => ({ text, ja })) }]
  })
}

export function createClaudePassageWriter({
  apiKey,
  model = DEFAULT_MODEL,
}: {
  apiKey: string
  model?: string
}): PassageWriter {
  const client = new Anthropic({ apiKey, timeout: PASSAGES_TIMEOUT_MS, maxRetries: 1 })

  return {
    async write(words: PassageWord[]): Promise<GeneratedPassages[]> {
      const response = await client.beta.messages.create({
        model,
        max_tokens: 16000,
        betas: ['server-side-fallback-2026-07-01'],
        // 安全のための拒否が起きたら、おすすめの別モデルでサーバー側が再実行する
        fallbacks: 'default',
        system: [{ type: 'text', text: PASSAGE_INSTRUCTIONS, cache_control: { type: 'ephemeral' } }],
        output_config: { effort: 'low', format: { type: 'json_schema', schema: OUTPUT_SCHEMA } },
        messages: [{ role: 'user', content: passagesUserMessage(words) }],
      })

      if (response.stop_reason === 'refusal') throw new Error('AI が回答を断りました')
      if (response.stop_reason === 'max_tokens') throw new Error('AI の返事が途中で切れました')
      const body = response.content.flatMap((block) => (block.type === 'text' ? [block.text] : [])).join('')
      return parsePassagesOutput(JSON.parse(body))
    },
  }
}
