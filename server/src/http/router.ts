// メソッド + パスのパターン（`/admin/groups/:id` など）の表と照合関数。
// Web フレームワークの代わりの最小限のルーター。

export type Params = Record<string, string>

export type RouteContext = {
  params: Params
  url: URL
}

export type Handler = (request: Request, context: RouteContext) => Response | Promise<Response>

export type Route = {
  method: string
  pattern: string
  handler: Handler
}

type CompiledRoute = Route & {
  regex: RegExp
  paramNames: string[]
}

export type MatchResult =
  | { kind: 'found'; handler: Handler; params: Params }
  | { kind: 'method-not-allowed'; allow: string[] }
  | { kind: 'not-found' }

const PARAM_SEGMENT = /^:([A-Za-z_][A-Za-z0-9_]*)$/

function escapeRegex(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function compile(route: Route): CompiledRoute {
  if (!route.pattern.startsWith('/')) {
    throw new Error(`パターンは / で始める: ${route.pattern}`)
  }
  const paramNames: string[] = []
  const segments = route.pattern
    .split('/')
    .slice(1)
    .map((segment) => {
      const param = PARAM_SEGMENT.exec(segment)
      if (param) {
        paramNames.push(param[1])
        return '([^/]+)'
      }
      return escapeRegex(segment)
    })
  return {
    ...route,
    method: route.method.toUpperCase(),
    regex: new RegExp(`^/${segments.join('/')}$`),
    paramNames,
  }
}

export class Router {
  private readonly routes: CompiledRoute[]

  constructor(routes: Route[]) {
    this.routes = routes.map(compile)
  }

  match(method: string, pathname: string): MatchResult {
    const upper = method.toUpperCase()
    const allow = new Set<string>()

    for (const route of this.routes) {
      const m = route.regex.exec(pathname)
      if (!m) continue

      const params: Params = {}
      let decodable = true
      route.paramNames.forEach((name, i) => {
        try {
          params[name] = decodeURIComponent(m[i + 1])
        } catch {
          decodable = false
        }
      })
      if (!decodable) continue

      // HEAD は GET のルートで答える（本文はアダプタが書かない）
      if (route.method === upper || (upper === 'HEAD' && route.method === 'GET')) {
        return { kind: 'found', handler: route.handler, params }
      }
      allow.add(route.method)
      if (route.method === 'GET') allow.add('HEAD')
    }

    if (allow.size > 0) return { kind: 'method-not-allowed', allow: [...allow].sort() }
    return { kind: 'not-found' }
  }
}
