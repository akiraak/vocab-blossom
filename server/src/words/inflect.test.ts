import { describe, expect, it } from 'vitest'
import { countHeadword, ellipsisSegments, findHeadword } from './inflect.ts'

/** 見出し語の区切りごとの表記 */
const parts = (text: string, headword: string) => findHeadword(text, headword)?.parts.map((p) => p.surface)

describe('findHeadword', () => {
  it('ふつうの見出し語は、全体と同じ場所を 1 つだけ parts に入れる', () => {
    const match = findHeadword('She plays tennis.', 'play')
    expect(match).toMatchObject({ surface: 'plays', start: 4, end: 9 })
    expect(match?.parts).toEqual([{ surface: 'plays', start: 4, end: 9 }])
  })

  it('「…」を含む見出し語は、間に語を挟んで区切りごとに見つける', () => {
    expect(parts('You can have either cake or ice cream.', 'either … or …')).toEqual(['either', 'or'])
    expect(parts('He can neither swim nor ride a bike.', 'neither … nor …')).toEqual(['neither', 'nor'])
    expect(parts('She is not only smart but also kind.', 'not only … but also …')).toEqual(['not only', 'but also'])
    expect(parts('Both my father and my mother are teachers.', 'both … and …')).toEqual(['Both', 'and'])
  })

  it('「…」の区切りの位置と、全体の範囲を返す', () => {
    const text = 'You can have either cake or ice cream.'
    const match = findHeadword(text, 'either … or …')!
    expect(text.slice(match.start, match.end)).toBe('either cake or')
    for (const part of match.parts) expect(text.slice(part.start, part.end)).toBe(part.surface)
  })

  it('「...」（ピリオド 3 つ）も「…」と同じに扱う', () => {
    expect(parts('You can have either cake or ice cream.', 'either ... or ...')).toEqual(['either', 'or'])
  })

  it('区切りがほかの語の一部なら当たらない', () => {
    expect(findHeadword('Either orange juice is fine.', 'either … or …')).toBeNull()
  })

  it('間に語が無い・間が長すぎるときは当たらない', () => {
    expect(findHeadword('Either or is fine.', 'either … or …')).toBeNull()
    expect(findHeadword('Either one two three four five six seven or eight.', 'either … or …')).toBeNull()
  })

  it('区切りの片方しか無ければ当たらない', () => {
    expect(findHeadword('I have both cats.', 'both … and …')).toBeNull()
  })
})

describe('countHeadword', () => {
  it('「…」を含む見出し語は、組になって出た回数を数える（片方だけの and などは数えない）', () => {
    expect(countHeadword('Both my father and my mother are teachers, and I am a teacher too.', 'both … and …')).toBe(1)
    expect(countHeadword('You can have either tea or coffee. Either Tom or Ken will come.', 'either … or …')).toBe(2)
    expect(countHeadword('He drinks tea or coffee.', 'either … or …')).toBe(0)
  })
})

describe('ellipsisSegments', () => {
  it('「…」で区切り、空の区切りは捨てる', () => {
    expect(ellipsisSegments('not only … but also …')).toEqual(['not only', 'but also'])
    expect(ellipsisSegments('Either ... or ...')).toEqual(['either', 'or'])
  })

  it('「…」が無ければ null', () => {
    expect(ellipsisSegments('as soon as')).toBeNull()
  })
})
