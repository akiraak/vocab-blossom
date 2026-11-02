import type { IncomingMessage, ServerResponse } from 'node:http'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import type { ReadableStream as NodeReadableStream } from 'node:stream/web'
import type { Handle } from '../app.ts'

// node:http と Web 標準の Request / Response の変換（薄いアダプタ）

export function toWebRequest(req: IncomingMessage): Request {
  const host = req.headers.host ?? 'localhost'
  const url = new URL(req.url ?? '/', `http://${host}`)

  const headers = new Headers()
  for (const [name, value] of Object.entries(req.headers)) {
    if (value === undefined) continue
    if (Array.isArray(value)) {
      for (const v of value) headers.append(name, v)
    } else {
      headers.set(name, value)
    }
  }

  const method = req.method ?? 'GET'
  const hasBody = method !== 'GET' && method !== 'HEAD'
  return new Request(url, {
    method,
    headers,
    body: hasBody ? (Readable.toWeb(req) as ReadableStream<Uint8Array>) : undefined,
    // ストリームを本文にするときに必要（Node の fetch 実装の要件）
    duplex: hasBody ? 'half' : undefined,
  } as RequestInit)
}

export async function writeWebResponse(
  res: ServerResponse,
  response: Response,
  method: string,
): Promise<void> {
  res.statusCode = response.status
  // set-cookie は複数になり得るので個別に扱う
  const cookies = response.headers.getSetCookie()
  if (cookies.length > 0) res.setHeader('set-cookie', cookies)
  response.headers.forEach((value, name) => {
    if (name !== 'set-cookie') res.setHeader(name, value)
  })

  if (method === 'HEAD' || response.body === null) {
    res.end()
    return
  }
  await pipeline(Readable.fromWeb(response.body as NodeReadableStream<Uint8Array>), res)
}

/** node:http の createServer に渡すリスナーを作る */
export function nodeListener(handle: Handle, onError: (error: unknown) => void) {
  return (req: IncomingMessage, res: ServerResponse): void => {
    void (async () => {
      let request: Request
      try {
        request = toWebRequest(req)
      } catch {
        // Host ヘッダが壊れているなど URL を組み立てられない
        res.statusCode = 400
        res.end('bad request')
        return
      }
      const response = await handle(request)
      await writeWebResponse(res, response, request.method)
    })().catch((error: unknown) => {
      onError(error)
      if (!res.headersSent) {
        res.statusCode = 500
        res.end('internal server error')
      } else {
        res.destroy()
      }
    })
  }
}
