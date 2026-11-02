import { describe, expect, it } from 'vitest'
import { withErrorHandling } from './app.ts'
import { TEST_ORIGIN, TEST_SECRET, apiReq, createTestApp, req } from './test-helpers.ts'

describe('/health', () => {
  it('認証なしで 200', async () => {
    const { handle } = createTestApp({ adminEnabled: false })
    const res = await handle(req('/health'))
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ ok: true })
  })
})

describe('/api/* の Bearer 認証', () => {
  it('Authorization なしは 401', async () => {
    const { handle } = createTestApp()
    const res = await handle(req('/api/ping'))
    expect(res.status).toBe(401)
    expect(res.headers.get('www-authenticate')).toBe('Bearer')
  })

  it('違うシークレットは 401', async () => {
    const { handle } = createTestApp()
    for (const value of [`Bearer ${TEST_SECRET}x`, 'Bearer ', `Basic ${TEST_SECRET}`, TEST_SECRET]) {
      const res = await handle(req('/api/ping', { headers: { authorization: value } }))
      expect(res.status, value).toBe(401)
    }
  })

  it('正しいシークレットなら 200', async () => {
    const { handle } = createTestApp()
    const res = await handle(apiReq('/api/ping'))
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ ok: true })
  })

  it('未定義の API パスでも認証が先（ルートの有無を漏らさない）', async () => {
    const { handle } = createTestApp()
    expect((await handle(req('/api/nope'))).status).toBe(401)
    expect((await handle(apiReq('/api/nope'))).status).toBe(404)
  })

  it('/apiary のような別のパスは /api 扱いしない', async () => {
    const { handle } = createTestApp()
    expect((await handle(req('/apiary'))).status).toBe(404)
  })
})

describe('/admin/* と ADMIN_ENABLED', () => {
  it('ADMIN_ENABLED が無効なら /admin 以下はすべて 404', async () => {
    const { handle } = createTestApp({ adminEnabled: false })
    for (const path of ['/admin', '/admin/groups', '/admin/nope']) {
      expect((await handle(req(path))).status, path).toBe(404)
    }
  })

  it('有効なら管理画面を返す', async () => {
    const { handle } = createTestApp()
    const top = await handle(req('/admin'))
    expect(top.status).toBe(302)
    expect(top.headers.get('location')).toBe('/admin/groups')

    const res = await handle(req('/admin/groups'))
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toBe('text/html; charset=utf-8')
    expect(await res.text()).toContain('<h1>グループ</h1>')
  })

  it('Origin が違う・無い POST は 403、同じなら通る', async () => {
    const { handle } = createTestApp()
    const post = (headers: Record<string, string>) =>
      handle(req('/admin/groups', { method: 'POST', headers }))

    expect((await post({})).status).toBe(403)
    expect((await post({ origin: 'https://evil.example' })).status).toBe(403)
    expect((await post({ origin: 'null' })).status).toBe(403)
    // 自分のホストからなら CSRF の関所は通る（このルートは POST 未定義なので 405）
    expect((await post({ origin: TEST_ORIGIN })).status).toBe(405)
    // Cloudflare 経由ではブラウザは https、コンテナには http で届く。ホストだけ比べる
    expect((await post({ origin: TEST_ORIGIN.replace('http:', 'https:') })).status).toBe(405)
  })

  it('メソッド違いは 405 と Allow', async () => {
    const { handle } = createTestApp()
    const res = await handle(req('/admin/groups', { method: 'PUT', headers: { origin: TEST_ORIGIN } }))
    expect(res.status).toBe(405)
    expect(res.headers.get('allow')).toBe('GET, HEAD')
  })
})

describe('エラー処理とアクセスログ', () => {
  it('未定義のパスは 404', async () => {
    const { handle } = createTestApp()
    expect((await handle(req('/nope'))).status).toBe(404)
  })

  it('1 リクエスト 1 行のアクセスログ（クエリは出さない）', async () => {
    const { handle, logs } = createTestApp()
    await handle(req('/health?q=secret-word'))
    expect(logs).toHaveLength(1)
    expect(logs[0]).toMatch(/^GET \/health 200 \d+ms$/)
  })

  it('ハンドラの例外は 500 にしてログに出す', async () => {
    const errors: string[] = []
    const logs: string[] = []
    let t = 1000
    const handle = withErrorHandling(
      async () => {
        t += 7
        throw new Error('boom')
      },
      { info: (m) => logs.push(m), error: (m) => errors.push(m) },
      () => t,
    )
    const res = await handle(req('/admin/groups'))
    expect(res.status).toBe(500)
    expect(await res.text()).toBe('internal server error')
    expect(errors).toEqual([`[error] GET ${TEST_ORIGIN}/admin/groups`])
    expect(logs).toEqual(['GET /admin/groups 500 7ms'])
  })
})
