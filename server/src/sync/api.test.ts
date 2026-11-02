import { describe, expect, it } from 'vitest'
import { apiReq, createTestApp, req } from '../test-helpers.ts'
import { SYNC_BODY_LIMIT } from './api.ts'

const GROUP_ID = '3F2504E0-4F89-11D3-9A0C-0305E82C3301'

const post = (body: string, headers: Record<string, string> = {}) =>
  apiReq('/api/sync', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body,
  })

describe('POST /api/sync', () => {
  it('Bearer なしは 401', async () => {
    const { handle } = createTestApp()
    const res = await handle(req('/api/sync', { method: 'POST', body: '{}' }))
    expect(res.status).toBe(401)
  })

  it('GET は 405', async () => {
    const { handle } = createTestApp()
    const res = await handle(apiReq('/api/sync'))
    expect(res.status).toBe(405)
    expect(res.headers.get('allow')).toBe('POST')
  })

  it('端末の変更を保存し、サーバーの今の状態と cursor を返す', async () => {
    const { handle } = createTestApp()
    const res = await handle(
      post(
        JSON.stringify({
          cursor: 0,
          groups: [{ id: GROUP_ID, name: '旅行', wordIds: ['a1-apple'], createdAt: 1, updatedAt: 2 }],
        }),
      ),
    )
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toBe('application/json; charset=utf-8')
    expect(await res.json()).toEqual({
      cursor: 1,
      reset: false,
      groups: [
        { id: GROUP_ID.toLowerCase(), name: '旅行', wordIds: ['a1-apple'], createdAt: 1, updatedAt: 2 },
      ],
      customWords: [],
      deletions: [],
    })

    // 別の端末（cursor 0）にも届く
    const other = await handle(post('{"cursor":0}'))
    expect(((await other.json()) as { groups: unknown[] }).groups).toHaveLength(1)
  })

  it('JSON でなければ 400', async () => {
    const { handle } = createTestApp()
    const res = await handle(post('{not json'))
    expect(res.status).toBe(400)
    expect(await res.json()).toEqual({ error: 'JSON ではない' })
  })

  it('形が違えば 400 で、何も保存しない', async () => {
    const { handle, db } = createTestApp()
    const res = await handle(
      post(
        JSON.stringify({
          groups: [
            { id: GROUP_ID, name: 'ok', wordIds: [], createdAt: 1, updatedAt: 2 },
            { id: 'not-a-uuid', name: 'ng', wordIds: [], createdAt: 1, updatedAt: 2 },
          ],
        }),
      ),
    )
    expect(res.status).toBe(400)
    expect(((await res.json()) as { error: string }).error).toContain('groups[1].id')
    expect(db.prepare('SELECT COUNT(*) AS n FROM groups').get()).toEqual({ n: 0 })
  })

  it('本文が上限を超えたら 413', async () => {
    const { handle } = createTestApp()
    const big = JSON.stringify({ groups: [], pad: 'x'.repeat(SYNC_BODY_LIMIT) })
    expect((await handle(post(big))).status).toBe(413)
    // Content-Length を偽っても読みながら止める
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(big))
        controller.close()
      },
    })
    const res = await handle(
      apiReq('/api/sync', { method: 'POST', body: stream, duplex: 'half' } as RequestInit),
    )
    expect(res.status).toBe(413)
  })
})
