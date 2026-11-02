// リクエスト本文を上限つきで読む。上限を超えたら読むのをやめて PayloadTooLargeError を投げる

export class PayloadTooLargeError extends Error {}
export class InvalidJsonError extends Error {}

export async function readText(request: Request, maxBytes: number): Promise<string> {
  const declared = Number(request.headers.get('content-length'))
  if (Number.isFinite(declared) && declared > maxBytes) throw new PayloadTooLargeError()
  if (request.body === null) return ''

  const reader = request.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    total += value.byteLength
    if (total > maxBytes) {
      await reader.cancel()
      throw new PayloadTooLargeError()
    }
    chunks.push(value)
  }
  return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))
}

export async function readJson(request: Request, maxBytes: number): Promise<unknown> {
  let body: string
  try {
    body = await readText(request, maxBytes)
  } catch (error) {
    if (error instanceof TypeError) throw new InvalidJsonError('UTF-8 ではない')
    throw error
  }
  try {
    return JSON.parse(body)
  } catch {
    throw new InvalidJsonError('JSON ではない')
  }
}
