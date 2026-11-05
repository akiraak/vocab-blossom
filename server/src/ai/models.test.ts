import { describe, expect, it } from 'vitest'
import { CLAUDE_MODELS, ModelInputError, TTS_MODELS, parseModel } from './models.ts'

describe('parseModel', () => {
  it('許可リストのモデルを返し、無ければ undefined', () => {
    expect(parseModel({ model: 'claude-sonnet-5-5' }, CLAUDE_MODELS)).toBe('claude-sonnet-5-5')
    expect(parseModel({ model: 'gemini-3.8-flash-lite-tts' }, TTS_MODELS)).toBe('gemini-3.8-flash-lite-tts')
    expect(parseModel({}, CLAUDE_MODELS)).toBeUndefined()
    expect(parseModel({ model: null }, CLAUDE_MODELS)).toBeUndefined()
    expect(parseModel(null, CLAUDE_MODELS)).toBeUndefined()
  })

  it('許可リストに無い・文字列でないモデルは ModelInputError', () => {
    expect(() => parseModel({ model: 'claude-haiku-5-5' }, CLAUDE_MODELS)).toThrow(ModelInputError)
    expect(() => parseModel({ model: 'gemini-3.8-flash-tts' }, CLAUDE_MODELS)).toThrow(ModelInputError)
    expect(() => parseModel({ model: 'claude-opus-5-5' }, TTS_MODELS)).toThrow(ModelInputError)
    expect(() => parseModel({ model: 1 }, TTS_MODELS)).toThrow(ModelInputError)
  })
})
