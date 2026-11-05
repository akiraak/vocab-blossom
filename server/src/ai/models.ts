// iOS の設定画面で選べる AI のモデル（リクエストの model）。ここに無いモデルは 400 にする。
// model が無いリクエスト（古いアプリ・管理画面）は今までどおり env（無ければ各ファイルの既定）を使う。
// 選んだ理由は docs/plans/archive/ai-model-settings.md

/** 自作語の AI チェック・穴埋めの文章 */
export const CLAUDE_MODELS = ['claude-opus-5-5', 'claude-sonnet-5-5'] as const
export type ClaudeModel = (typeof CLAUDE_MODELS)[number]

/** 読み上げの声。3.1 / 2.5 は今の呼び方（Interactions API・speech_metadata・audio/l16）に対応していない */
export const TTS_MODELS = ['gemini-3.8-flash-tts', 'gemini-3.8-flash-lite-tts'] as const
export type TtsModel = (typeof TTS_MODELS)[number]

export class ModelInputError extends Error {}

/** リクエストの本文から model を取り出す。無ければ undefined、許可リストに無ければ ModelInputError */
export function parseModel<T extends string>(body: unknown, allowed: readonly T[]): T | undefined {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return undefined
  const value = (body as Record<string, unknown>).model
  if (value === undefined || value === null) return undefined
  if (typeof value !== 'string' || !(allowed as readonly string[]).includes(value)) {
    throw new ModelInputError(`model が不正です（${allowed.join(' / ')} のどれか）`)
  }
  return value as T
}
