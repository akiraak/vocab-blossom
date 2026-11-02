import { InvalidJsonError, PayloadTooLargeError, readJson } from '../http/body.ts'
import { json } from '../http/responses.ts'
import type { Handler } from '../http/router.ts'
import type { SyncStore } from './store.ts'
import { ValidationError, parseSyncRequest } from './types.ts'

// POST /api/sync（Bearer の確認は app.ts の関所で済んでいる）

export const SYNC_BODY_LIMIT = 5 * 1024 * 1024

export function syncHandler(store: SyncStore): Handler {
  return async (request) => {
    let body: unknown
    try {
      body = await readJson(request, SYNC_BODY_LIMIT)
    } catch (error) {
      if (error instanceof PayloadTooLargeError) return json({ error: 'payload too large' }, 413)
      if (error instanceof InvalidJsonError) return json({ error: error.message }, 400)
      throw error
    }

    let syncRequest
    try {
      syncRequest = parseSyncRequest(body)
    } catch (error) {
      if (error instanceof ValidationError) return json({ error: error.message }, 400)
      throw error
    }

    return json(store.sync(syncRequest))
  }
}
