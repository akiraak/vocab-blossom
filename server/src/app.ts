import type { Config } from './config.ts'
import type { DB } from './db.ts'
import { isAuthorizedBearer } from './http/auth.ts'
import { isSafeMethod, isSameOrigin } from './http/csrf.ts'
import { html, layout } from './http/html.ts'
import { htmlPage, json, notFound, redirect, text } from './http/responses.ts'
import { type Route, Router } from './http/router.ts'
import { syncHandler } from './sync/api.ts'
import { SyncStore } from './sync/store.ts'

// サーバー本体。Web 標準の Request を受けて Response を返す関数（handle）として書き、
// node:http との変換は http/adapter.ts に閉じ込める。テストは handle(new Request(...)) で書く。

export type Logger = {
  info: (message: string) => void
  error: (message: string, error?: unknown) => void
}

export const consoleLogger: Logger = {
  info: (message) => console.log(message),
  error: (message, error) => console.error(message, error ?? ''),
}

export type AppDeps = {
  config: Config
  db: DB
  logger?: Logger
  now?: () => number
}

export type Handle = (request: Request) => Promise<Response>

function isUnder(pathname: string, prefix: string): boolean {
  return pathname === prefix || pathname.startsWith(`${prefix}/`)
}

export function createApp({ config, db, logger = consoleLogger, now = Date.now }: AppDeps): Handle {
  const store = new SyncStore(db)
  const routes: Route[] = [
    { method: 'GET', pattern: '/health', handler: () => json({ ok: true }) },

    // iOS 用 API（Bearer 必須）。ping は設定の確認用
    { method: 'GET', pattern: '/api/ping', handler: () => json({ ok: true }) },
    { method: 'POST', pattern: '/api/sync', handler: syncHandler(store) },

    // 管理画面（Cloudflare Access + ADMIN_ENABLED=on）。画面は Phase 3
    { method: 'GET', pattern: '/admin', handler: () => redirect('/admin/groups', 302) },
    {
      method: 'GET',
      pattern: '/admin/groups',
      handler: () =>
        htmlPage(
          layout({
            title: 'グループ',
            body: html`<h1>グループ</h1><p>管理画面は準備中です。</p>`,
          }),
        ),
    },
  ]
  const router = new Router(routes)

  // 認証・CSRF などパスの区分ごとの関所。通すなら null を返す
  function guard(request: Request, url: URL): Response | null {
    if (isUnder(url.pathname, '/api')) {
      if (!isAuthorizedBearer(request, config.apiSharedSecret)) {
        return json({ error: 'unauthorized' }, 401, { 'www-authenticate': 'Bearer' })
      }
    }
    if (isUnder(url.pathname, '/admin')) {
      // 無効のときは存在しないものとして扱う（fail-safe）
      if (!config.adminEnabled) return notFound()
      if (!isSafeMethod(request.method) && !isSameOrigin(request)) {
        return text('forbidden: origin mismatch', 403)
      }
    }
    return null
  }

  async function dispatch(request: Request): Promise<Response> {
    const url = new URL(request.url)
    const blocked = guard(request, url)
    if (blocked) return blocked

    const match = router.match(request.method, url.pathname)
    switch (match.kind) {
      case 'found':
        return match.handler(request, { params: match.params, url })
      case 'method-not-allowed':
        return text('method not allowed', 405, { allow: match.allow.join(', ') })
      case 'not-found':
        return notFound()
    }
  }

  return withErrorHandling(dispatch, logger, now)
}

/** 例外を 500 にしてログに出し、1 リクエスト 1 行のアクセスログを書く */
export function withErrorHandling(dispatch: Handle, logger: Logger, now: () => number = Date.now): Handle {
  return async function handle(request: Request): Promise<Response> {
    const started = now()
    let response: Response
    try {
      response = await dispatch(request)
    } catch (error) {
      logger.error(`[error] ${request.method} ${request.url}`, error)
      response = text('internal server error', 500)
    }
    // クエリには検索語などが入るのでパスだけ出す
    const { pathname } = new URL(request.url)
    logger.info(`${request.method} ${pathname} ${response.status} ${now() - started}ms`)
    return response
  }
}
