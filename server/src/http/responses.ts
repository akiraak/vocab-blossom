import type { SafeHtml } from './html.ts'

export function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  })
}

export function text(body: string, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(body, {
    status,
    headers: { 'content-type': 'text/plain; charset=utf-8', ...headers },
  })
}

export function htmlPage(body: SafeHtml, status = 200): Response {
  return new Response(body.value, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  })
}

export function redirect(location: string, status = 303): Response {
  return new Response(null, { status, headers: { location } })
}

export const notFound = (): Response => text('not found', 404)
