import Anthropic from '@anthropic-ai/sdk'
import { DEFAULT_MODEL } from './claude.ts'
import { BLANK, type CheckQuestion, type CheckVerdict, type ChoiceJudge } from './fill-blank-checks.ts'
import type { ClaudeModel } from './models.ts'

// Claude API で穴埋めの選択肢を判定する。文章を作る指示（claude-passages.ts）とは別の指示にして、
// 作った側の思い込みに引きずられないようにする。システムプロンプトは毎回同じ文字列にしてキャッシュを効かせる。

/** iOS が待てる時間に収める（10 問・SDK の再試行 1 回を含めて 1 分強） */
export const CHECK_TIMEOUT_MS = 35_000

export const CHECK_INSTRUCTIONS = `You review four-choice fill-in-the-blank questions in an English vocabulary app for Japanese beginners (CEFR A1–A2).
Each question has a short passage with a blank (${BLANK}), the intended answer, and some other choices.
A paired expression such as "either … or …" is blanked in each part, and a choice fills the blanks in the same way.

For each other choice, decide whether it is ALSO a correct answer: put it in the blank and read the whole passage.
- fits = true only if the sentence is grammatical, sounds natural, and the passage still makes sense as a whole
  (logically consistent with the other sentences), so an English teacher would have to mark it correct.
- fits = false if it is ungrammatical (wrong part of speech, wrong word order, missing "of" / "to", a phrase that cannot take a clause, etc.),
  unnatural, or contradicts the situation, the reason, the result or the contrast in the other sentences.
- Ignore capitalization at the start of a sentence and small spacing differences.
- Judge strictly but fairly: a different meaning is fine as long as the passage still makes sense; do not accept a choice just because it is "almost" right.

Each input line is a JSON object with id, passage, answer and choices. Return one item per input line with the same id,
and one verdict per choice with the choice written exactly as given.`

const OUTPUT_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdicts: {
            type: 'array',
            items: {
              type: 'object',
              properties: { word: { type: 'string' }, fits: { type: 'boolean' } },
              required: ['word', 'fits'],
              additionalProperties: false,
            },
          },
        },
        required: ['id', 'verdicts'],
        additionalProperties: false,
      },
    },
  },
  required: ['items'],
  additionalProperties: false,
}

export function checkUserMessage(questions: CheckQuestion[]): string {
  return questions
    .map((q) => JSON.stringify({ id: q.id, passage: q.blanked, answer: q.answer, choices: q.candidates }))
    .join('\n')
}

/** AI の返事（JSON）を形だけ確かめる */
export function parseCheckOutput(value: unknown): CheckVerdict[] {
  const items = (value as { items?: unknown })?.items
  if (!Array.isArray(items)) throw new Error('items がありません')
  return items.flatMap((item) => {
    const { id, verdicts } = (item ?? {}) as { id?: unknown; verdicts?: unknown }
    if (typeof id !== 'string' || !Array.isArray(verdicts)) return []
    const valid = verdicts.filter(
      (v): v is { word: string; fits: boolean } => typeof v?.word === 'string' && typeof v?.fits === 'boolean',
    )
    return [{ id, verdicts: valid.map(({ word, fits }) => ({ word, fits })) }]
  })
}

export function createClaudeChoiceJudge({ apiKey, model = DEFAULT_MODEL }: { apiKey: string; model?: string }): ChoiceJudge {
  const client = new Anthropic({ apiKey, timeout: CHECK_TIMEOUT_MS, maxRetries: 1 })

  return {
    async judge(questions: CheckQuestion[], requestModel?: ClaudeModel): Promise<CheckVerdict[]> {
      const response = await client.beta.messages.create({
        model: requestModel ?? model,
        max_tokens: 8000,
        betas: ['server-side-fallback-2026-07-01'],
        // 安全のための拒否が起きたら、おすすめの別モデルでサーバー側が再実行する
        fallbacks: 'default',
        system: [{ type: 'text', text: CHECK_INSTRUCTIONS, cache_control: { type: 'ephemeral' } }],
        // 文法の細かい違いを見るので、文章を作るとき（low）より考えさせる
        output_config: { effort: 'medium', format: { type: 'json_schema', schema: OUTPUT_SCHEMA } },
        messages: [{ role: 'user', content: checkUserMessage(questions) }],
      })

      if (response.stop_reason === 'refusal') throw new Error('AI が回答を断りました')
      if (response.stop_reason === 'max_tokens') throw new Error('AI の返事が途中で切れました')
      const body = response.content.flatMap((block) => (block.type === 'text' ? [block.text] : [])).join('')
      return parseCheckOutput(JSON.parse(body))
    },
  }
}
