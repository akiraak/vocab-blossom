import { createHash, timingSafeEqual } from 'node:crypto'

// `Authorization: Bearer <secret>` を一定時間で照合する。
// 長さの違いで早く返らないよう、両方を SHA-256 にして同じ長さで比べる。

function digest(value: string): Buffer {
  return createHash('sha256').update(value, 'utf8').digest()
}

export function bearerToken(request: Request): string | null {
  const header = request.headers.get('authorization')
  if (!header) return null
  const m = /^Bearer\s+(\S+)\s*$/i.exec(header)
  return m ? m[1] : null
}

export function isAuthorizedBearer(request: Request, secret: string): boolean {
  const token = bearerToken(request)
  if (token === null || secret === '') return false
  return timingSafeEqual(digest(token), digest(secret))
}
