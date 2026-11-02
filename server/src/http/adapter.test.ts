import { type Server, createServer } from 'node:http'
import type { AddressInfo } from 'node:net'
import { afterEach, describe, expect, it } from 'vitest'
import type { Handle } from '../app.ts'
import { nodeListener } from './adapter.ts'

// アダプタだけは実際に node:http で起動して確かめる

let server: Server | undefined

async function start(handle: Handle): Promise<string> {
  server = createServer(nodeListener(handle, () => {}))
  await new Promise<void>((resolve) => server!.listen(0, '127.0.0.1', resolve))
  const { port } = server.address() as AddressInfo
  return `http://127.0.0.1:${port}`
}

afterEach(async () => {
  await new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve()))
  server = undefined
})

describe('nodeListener', () => {
  it('メソッド・URL・ヘッダ・本文を Request にして、Response を書き戻す', async () => {
    let seen: { method: string; url: string; auth: string | null; body: string } | undefined
    const base = await start(async (request) => {
      seen = {
        method: request.method,
        url: request.url,
        auth: request.headers.get('authorization'),
        body: await request.text(),
      }
      const headers = new Headers({ 'content-type': 'application/json', 'x-test': '1' })
      headers.append('set-cookie', 'a=1')
      headers.append('set-cookie', 'b=2')
      return new Response('{"ok":true}', { status: 201, headers })
    })

    const res = await fetch(`${base}/api/sync?x=1`, {
      method: 'POST',
      headers: { authorization: 'Bearer t', 'content-type': 'application/json' },
      body: '{"cursor":0}',
    })
    expect(res.status).toBe(201)
    expect(res.headers.get('x-test')).toBe('1')
    expect(res.headers.getSetCookie()).toEqual(['a=1', 'b=2'])
    expect(await res.text()).toBe('{"ok":true}')
    expect(seen).toEqual({
      method: 'POST',
      url: `${base}/api/sync?x=1`,
      auth: 'Bearer t',
      body: '{"cursor":0}',
    })
  })

  it('HEAD には本文を書かない', async () => {
    const base = await start(async () => new Response('hello', { status: 200 }))
    const res = await fetch(`${base}/health`, { method: 'HEAD' })
    expect(res.status).toBe(200)
    expect(await res.text()).toBe('')
  })

  it('handle が投げても 500 を返す', async () => {
    const base = await start(async () => {
      throw new Error('boom')
    })
    const res = await fetch(`${base}/health`)
    expect(res.status).toBe(500)
  })
})
