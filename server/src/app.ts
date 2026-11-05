import type { Config } from './config.ts'
import type { DB } from './db.ts'
import { isAuthorizedBearer } from './http/auth.ts'
import { isSafeMethod, isSameOrigin } from './http/csrf.ts'
import { json, notFound, text } from './http/responses.ts'
import { type Route, Router } from './http/router.ts'
import { syncHandler } from './sync/api.ts'
import { SyncStore } from './sync/store.ts'
import { adminRoutes } from './admin/routes.ts'
import { AdminService } from './admin/service.ts'
import { BundledWords } from './words/bundled.ts'
import { createClaudeWordAssistant } from './ai/claude.ts'
import { createClaudePassageWriter } from './ai/claude-passages.ts'
import { PassageStore, type PassageWriter, passagesHandler } from './ai/passages.ts'
import { createGeminiSpeechSynthesizer } from './ai/gemini-tts.ts'
import { SPEECH_RATE_LIMIT, type SpeechSynthesizer, speechHandler } from './ai/speech.ts'
import {
  RATE_LIMIT,
  RATE_WINDOW_MS,
  RateLimiter,
  type WordAssistant,
  wordAssistHandler,
} from './ai/word-assist.ts'

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
  /** 同梱語。省略時は data/decks/*.json を読む */
  bundled?: BundledWords
  /** 自作語の AI チェック。省略時は ANTHROPIC_API_KEY があれば Claude、無ければ null（503） */
  assistant?: WordAssistant | null
  /** 穴埋め用の文章を作る AI。省略時は ANTHROPIC_API_KEY があれば Claude、無ければ null（ためた文章だけ返す） */
  passageWriter?: PassageWriter | null
  /** 読み上げの声。省略時は GEMINI_API_KEY があれば Gemini TTS、無ければ null（503） */
  speechSynthesizer?: SpeechSynthesizer | null
}

export type Handle = (request: Request) => Promise<Response>

function isUnder(pathname: string, prefix: string): boolean {
  return pathname === prefix || pathname.startsWith(`${prefix}/`)
}

export function createApp({
  config,
  db,
  logger = consoleLogger,
  now = Date.now,
  bundled = BundledWords.load(),
  assistant,
  passageWriter,
  speechSynthesizer,
}: AppDeps): Handle {
  const store = new SyncStore(db)
  const service = new AdminService({ db, store, bundled, now })
  const wordAssistant =
    assistant !== undefined
      ? assistant
      : config.anthropicApiKey
        ? createClaudeWordAssistant({ apiKey: config.anthropicApiKey, model: config.anthropicModel, bundled })
        : null
  const wordAssist = wordAssistHandler({
    assistant: wordAssistant,
    bundled,
    // iOS と管理画面で 1 つの枠を共有する
    limiter: new RateLimiter(RATE_LIMIT, RATE_WINDOW_MS, now),
    logError: (message, error) => logger.error(message, error),
  })
  const passages = passagesHandler({
    writer:
      passageWriter !== undefined
        ? passageWriter
        : config.anthropicApiKey
          ? createClaudePassageWriter({ apiKey: config.anthropicApiKey, model: config.anthropicModel })
          : null,
    store: new PassageStore(db),
    // AI チェックとは別の枠。AI を呼んだ回数で数える
    limiter: new RateLimiter(RATE_LIMIT, RATE_WINDOW_MS, now),
    now,
    logError: (message, error) => logger.error(message, error),
  })
  const speech = speechHandler({
    synthesizer:
      speechSynthesizer !== undefined
        ? speechSynthesizer
        : config.geminiApiKey
          ? createGeminiSpeechSynthesizer({ apiKey: config.geminiApiKey, model: config.geminiTtsModel })
          : null,
    // AI チェック・文章とは別の枠（1 文 1 回で数が多い）
    limiter: new RateLimiter(SPEECH_RATE_LIMIT, RATE_WINDOW_MS, now),
    logError: (message, error) => logger.error(message, error),
  })
  const routes: Route[] = [
    { method: 'GET', pattern: '/health', handler: () => json({ ok: true }) },

    // iOS 用 API（Bearer 必須）。ping は設定の確認用
    { method: 'GET', pattern: '/api/ping', handler: () => json({ ok: true }) },
    { method: 'POST', pattern: '/api/sync', handler: syncHandler(store) },
    { method: 'POST', pattern: '/api/word-assist', handler: wordAssist },
    { method: 'POST', pattern: '/api/passages', handler: passages },
    { method: 'POST', pattern: '/api/speech', handler: speech },

    // 管理画面のフォームから呼ぶ AI チェック（Access + ADMIN_ENABLED + Origin の確認は関所で）
    { method: 'POST', pattern: '/admin/word-assist', handler: wordAssist },

    // 管理画面（Cloudflare Access + ADMIN_ENABLED=on）
    ...adminRoutes({ service, bundled, aiEnabled: wordAssistant !== null }),
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
