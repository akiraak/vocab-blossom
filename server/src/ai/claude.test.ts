import { describe, expect, it } from 'vitest'
import { testBundled } from '../test-helpers.ts'
import { buildSystemPrompt } from './claude.ts'

describe('buildSystemPrompt', () => {
  it('同梱語の見出し語を 1 行ずつ重複なく含み、毎回同じ文字列になる（キャッシュが効く）', () => {
    const bundled = testBundled()
    const prompt = buildSystemPrompt(bundled)
    expect(buildSystemPrompt(bundled)).toBe(prompt)
    const lines = new Set(prompt.split('\n'))
    for (const word of ['beautiful', 'go', 'take care of']) {
      if (bundled.findBySpelling(word)) expect(lines.has(word), word).toBe(true)
    }
    const listed = prompt.split('Built-in word list (one entry per line):\n')[1].split('\n')
    expect(listed).toHaveLength(new Set(bundled.all.map((w) => w.word)).size)
  })
})
