import { describe, expect, it } from 'vitest'
import { Router } from './router.ts'

const ok = () => new Response('ok')

describe('Router', () => {
  const router = new Router([
    { method: 'GET', pattern: '/admin/groups', handler: ok },
    { method: 'POST', pattern: '/admin/groups', handler: ok },
    { method: 'GET', pattern: '/admin/groups/:id', handler: ok },
    { method: 'POST', pattern: '/admin/groups/:id/words/:wordId', handler: ok },
    { method: 'DELETE', pattern: '/a.b', handler: ok },
  ])

  it('一致するルートとパスのパラメータを返す', () => {
    const m = router.match('GET', '/admin/groups/g-1')
    expect(m.kind).toBe('found')
    if (m.kind === 'found') expect(m.params).toEqual({ id: 'g-1' })

    const m2 = router.match('post', '/admin/groups/g%201/words/a1-0001')
    expect(m2.kind).toBe('found')
    if (m2.kind === 'found') expect(m2.params).toEqual({ id: 'g 1', wordId: 'a1-0001' })
  })

  it('未定義のパスは not-found', () => {
    expect(router.match('GET', '/admin/nope').kind).toBe('not-found')
    expect(router.match('GET', '/admin/groups/').kind).toBe('not-found')
    expect(router.match('GET', '/admin/groups/a/b').kind).toBe('not-found')
  })

  it('パスは合うがメソッドが違えば method-not-allowed と Allow の一覧', () => {
    expect(router.match('PUT', '/admin/groups')).toEqual({
      kind: 'method-not-allowed',
      allow: ['GET', 'HEAD', 'POST'],
    })
  })

  it('HEAD は GET のルートで答える', () => {
    expect(router.match('HEAD', '/admin/groups/x').kind).toBe('found')
  })

  it('パターンの記号は正規表現として扱わない', () => {
    expect(router.match('DELETE', '/a.b').kind).toBe('found')
    expect(router.match('DELETE', '/axb').kind).toBe('not-found')
  })

  it('デコードできないパラメータは一致させない', () => {
    expect(router.match('GET', '/admin/groups/%E0%A4%A').kind).toBe('not-found')
  })
})
