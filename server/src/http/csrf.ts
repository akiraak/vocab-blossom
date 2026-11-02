// 管理画面の POST などは Cloudflare Access の後ろにあるが、念のため
// `Origin` ヘッダのホストが自分のホスト（Host ヘッダ）と一致するかを確かめる。
// cloudflared はブラウザが送った Host（vocab.chobi.me）をそのまま渡し、
// コンテナには http で届くので、スキームは比べずホストだけを比べる。

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS'])

export function isSafeMethod(method: string): boolean {
  return SAFE_METHODS.has(method.toUpperCase())
}

export function isSameOrigin(request: Request): boolean {
  const origin = request.headers.get('origin')
  if (!origin || origin === 'null') return false
  let originHost: string
  try {
    originHost = new URL(origin).host
  } catch {
    return false
  }
  const host = request.headers.get('host') ?? new URL(request.url).host
  return originHost.toLowerCase() === host.toLowerCase()
}
