// 同期するデータの型と、端末から届いた JSON の検証。
// 日時はすべてミリ秒の整数（UNIX エポック）。設計は docs/plans/archive/admin-server.md の「Phase 2 の詳細」。

/** iOS の `PartOfSpeech` と同じ並び */
export const PARTS_OF_SPEECH = [
  'noun',
  'verb',
  'adjective',
  'adverb',
  'preposition',
  'conjunction',
  'interjection',
  'number',
  'determiner',
  'pronoun',
  'modal',
  'phrase',
] as const

export type PartOfSpeech = (typeof PARTS_OF_SPEECH)[number]

export type Group = {
  /** UUID（小文字） */
  id: string
  name: string
  /** 同梱語・自作語の ID の並び（追加した順） */
  wordIds: string[]
  createdAt: number
  updatedAt: number
}

/** 意味 1 つ分（品詞・意味・例文・例文の訳）。iOS の `WordSense` と同じ形 */
export type WordSense = {
  pos: PartOfSpeech
  meaning: string
  example: string
  exampleJa: string
}

export type CustomWord = {
  /** `custom-` で始まる */
  wordId: string
  word: string
  /** 1 つ目の意味（品詞・意味・例文・訳） */
  meaning: string
  pos: PartOfSpeech
  example: string
  exampleJa: string
  /** 2 つ目以降の意味（commute の「名詞: 通勤」など）。無ければ空 */
  extraSenses: WordSense[]
  createdAt: number
  updatedAt: number
}

export type DeletionKind = 'group' | 'customWord'

export type Deletion = {
  kind: DeletionKind
  id: string
  deletedAt: number
}

export type SyncRequest = {
  cursor: number
  groups: Group[]
  customWords: CustomWord[]
  deletions: Deletion[]
}

export type SyncResponse = {
  cursor: number
  /** サーバーの DB が作り直されていた（端末は全件を送り直す） */
  reset: boolean
  groups: Group[]
  customWords: CustomWord[]
  deletions: Deletion[]
}

export const CUSTOM_WORD_PREFIX = 'custom-'

export const LIMITS = {
  /** 1 回の同期で送れるレコード数（種類ごと） */
  records: 10_000,
  wordIdsPerGroup: 10_000,
  id: 200,
  groupName: 200,
  word: 200,
  meaning: 500,
  example: 1000,
  /** 1 語に足せる意味の数（1 つ目を除く） */
  extraSenses: 10,
} as const

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

export class ValidationError extends Error {}

export function isCustomWordId(id: string): boolean {
  return id.startsWith(CUSTOM_WORD_PREFIX) && id.length > CUSTOM_WORD_PREFIX.length
}

/** グループの ID を正規化する（Swift の UUID は大文字で書き出すので小文字にそろえる）。不正なら null */
export function normalizeGroupId(value: string): string | null {
  const id = value.trim().toLowerCase()
  return UUID.test(id) ? id : null
}

/** 重複を除く（最初に出てきた位置を残す） */
export function uniqueIds(ids: string[]): string[] {
  return [...new Set(ids)]
}

// --- 検証の小道具 ---

type Obj = Record<string, unknown>

function isObject(value: unknown): value is Obj {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function fail(path: string, message: string): never {
  throw new ValidationError(`${path}: ${message}`)
}

function object(value: unknown, path: string): Obj {
  if (!isObject(value)) fail(path, 'オブジェクトではない')
  return value
}

function str(obj: Obj, key: string, path: string, max: number, { required = true } = {}): string {
  const value = obj[key]
  if (value === undefined && !required) return ''
  if (typeof value !== 'string') fail(`${path}.${key}`, '文字列ではない')
  const trimmed = value.trim()
  if (required && trimmed === '') fail(`${path}.${key}`, '空')
  if (trimmed.length > max) fail(`${path}.${key}`, `${max} 文字を超えている`)
  return trimmed
}

function time(obj: Obj, key: string, path: string): number {
  const value = obj[key]
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    fail(`${path}.${key}`, 'ミリ秒の整数ではない')
  }
  return value
}

function array(value: unknown, path: string, max: number): unknown[] {
  if (value === undefined) return []
  if (!Array.isArray(value)) fail(path, '配列ではない')
  if (value.length > max) fail(path, `${max} 件を超えている`)
  return value
}

// --- レコードごとの検証 ---

export function parseGroup(value: unknown, path = 'group'): Group {
  const obj = object(value, path)
  const rawId = str(obj, 'id', path, LIMITS.id)
  const id = normalizeGroupId(rawId) ?? fail(`${path}.id`, 'UUID ではない')
  const wordIds = array(obj.wordIds ?? null, `${path}.wordIds`, LIMITS.wordIdsPerGroup).map(
    (wordId, i) => {
      if (typeof wordId !== 'string' || wordId === '' || wordId.length > LIMITS.id) {
        fail(`${path}.wordIds[${i}]`, '単語 ID ではない')
      }
      return wordId
    },
  )
  return {
    id,
    name: str(obj, 'name', path, LIMITS.groupName),
    wordIds: uniqueIds(wordIds),
    createdAt: time(obj, 'createdAt', path),
    updatedAt: time(obj, 'updatedAt', path),
  }
}

export function parseCustomWord(value: unknown, path = 'customWord'): CustomWord {
  const obj = object(value, path)
  const wordId = str(obj, 'wordId', path, LIMITS.id)
  if (!isCustomWordId(wordId)) fail(`${path}.wordId`, `${CUSTOM_WORD_PREFIX} で始まっていない`)
  // extraSenses が無いデータ（意味を複数持てるようになる前のアプリ）は、意味が 1 つの語として読む
  const extraSenses = array(obj.extraSenses, `${path}.extraSenses`, LIMITS.extraSenses).map(
    (sense, i) => parseSense(sense, `${path}.extraSenses[${i}]`),
  )
  return {
    wordId,
    word: str(obj, 'word', path, LIMITS.word),
    ...parseSense(obj, path),
    extraSenses,
    createdAt: time(obj, 'createdAt', path),
    updatedAt: time(obj, 'updatedAt', path),
  }
}

/** 意味 1 つ分。自作語の 1 つ目の意味（自作語そのものの pos・meaning…）にも使う */
export function parseSense(value: unknown, path = 'sense'): WordSense {
  const obj = object(value, path)
  const pos = obj.pos
  if (typeof pos !== 'string' || !(PARTS_OF_SPEECH as readonly string[]).includes(pos)) {
    fail(`${path}.pos`, '品詞ではない')
  }
  return {
    pos: pos as PartOfSpeech,
    meaning: str(obj, 'meaning', path, LIMITS.meaning),
    example: str(obj, 'example', path, LIMITS.example, { required: false }),
    exampleJa: str(obj, 'exampleJa', path, LIMITS.example, { required: false }),
  }
}

export function parseDeletion(value: unknown, path = 'deletion'): Deletion {
  const obj = object(value, path)
  const kind = obj.kind
  const rawId = str(obj, 'id', path, LIMITS.id)
  let id: string
  if (kind === 'group') {
    id = normalizeGroupId(rawId) ?? fail(`${path}.id`, 'UUID ではない')
  } else if (kind === 'customWord') {
    if (!isCustomWordId(rawId)) fail(`${path}.id`, `${CUSTOM_WORD_PREFIX} で始まっていない`)
    id = rawId
  } else {
    fail(`${path}.kind`, 'group / customWord のどちらでもない')
  }
  return { kind, id, deletedAt: time(obj, 'deletedAt', path) }
}

export function parseSyncRequest(value: unknown): SyncRequest {
  const obj = object(value, 'body')
  const cursor = obj.cursor ?? 0
  if (typeof cursor !== 'number' || !Number.isSafeInteger(cursor) || cursor < 0) {
    fail('body.cursor', '0 以上の整数ではない')
  }
  return {
    cursor,
    groups: array(obj.groups, 'groups', LIMITS.records).map((g, i) => parseGroup(g, `groups[${i}]`)),
    customWords: array(obj.customWords, 'customWords', LIMITS.records).map((w, i) =>
      parseCustomWord(w, `customWords[${i}]`),
    ),
    deletions: array(obj.deletions, 'deletions', LIMITS.records).map((d, i) =>
      parseDeletion(d, `deletions[${i}]`),
    ),
  }
}
