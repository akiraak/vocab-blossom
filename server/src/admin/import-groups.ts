import type { DB } from '../db.ts'
import { type BundledWords, normalizeSpelling } from '../words/bundled.ts'
import { AdminInputError, type AdminService, type SenseDraft, type WordDraft, normalizeGroupName } from './service.ts'

// グループと語を JSON からまとめて取り込む（data/groups/*.json）。CLI は server/src/import-groups.ts。
//
// 管理画面と同じ AdminService で書くので、アプリには同期で届く。
// 2 回動かしても増えない: 同じ名前のグループはそのまま使い、入っている語は飛ばし、
// 同じ綴りのマイ単語は中身が同じなら触らない（違えば中身を置き換える。ID はそのまま）。

/** 単語帳の語。綴りは取り違え防止の照合用 */
export type BundledInput = { bundled: string; word: string }
/** マイ単語として作る語 */
export type CustomInput = Omit<WordDraft, 'extraSenses'> & { extraSenses?: SenseDraft[] }
export type ImportInput = {
  groups: { name: string; words: (BundledInput | CustomInput)[] }[]
}

export type GroupReport = {
  name: string
  /** グループを新しく作った（false は同じ名前のグループを使った） */
  created: boolean
  /** グループに足した語（単語帳の語・マイ単語） */
  added: string[]
  /** すでにグループに入っていた語 */
  alreadyIn: string[]
  /** マイ単語を新しく作った */
  customCreated: string[]
  /** 同じ綴りのマイ単語の中身を置き換えた */
  customReplaced: string[]
}

export class ImportInputError extends Error {}

/** 取り込みを止めずに最後まで流し、書いた内容を取り消すための目印（--dry-run） */
class DryRunRollback extends Error {}

function fail(path: string, message: string): never {
  throw new ImportInputError(`${path}: ${message}`)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function stringField(obj: Record<string, unknown>, key: string, path: string, optional = false): string {
  const value = obj[key]
  if (value === undefined && optional) return ''
  if (typeof value !== 'string') fail(`${path}.${key}`, '文字列ではない')
  return value
}

function parseSense(value: unknown, path: string): SenseDraft {
  if (!isRecord(value)) fail(path, 'オブジェクトではない')
  return {
    pos: stringField(value, 'pos', path),
    meaning: stringField(value, 'meaning', path),
    example: stringField(value, 'example', path, true),
    exampleJa: stringField(value, 'exampleJa', path, true),
  }
}

/** JSON の形を確かめる。中身（品詞・文字数）は AdminService の検証に任せる */
export function parseImportInput(value: unknown): ImportInput {
  if (!isRecord(value) || !Array.isArray(value.groups)) fail('groups', '配列ではない')
  const groups = value.groups.map((group, gi) => {
    const path = `groups[${gi}]`
    if (!isRecord(group) || !Array.isArray(group.words)) fail(`${path}.words`, '配列ではない')
    const name = stringField(group, 'name', path)
    const words = group.words.map((word, wi): BundledInput | CustomInput => {
      const wordPath = `${path}.words[${wi}]`
      if (!isRecord(word)) fail(wordPath, 'オブジェクトではない')
      if (word.bundled !== undefined) {
        return { bundled: stringField(word, 'bundled', wordPath), word: stringField(word, 'word', wordPath) }
      }
      const extras = word.extraSenses ?? []
      if (!Array.isArray(extras)) fail(`${wordPath}.extraSenses`, '配列ではない')
      return {
        word: stringField(word, 'word', wordPath),
        ...parseSense(word, wordPath),
        extraSenses: extras.map((sense, si) => parseSense(sense, `${wordPath}.extraSenses[${si}]`)),
      }
    })
    return { name, words }
  })
  return { groups }
}

function isBundledInput(word: BundledInput | CustomInput): word is BundledInput {
  return 'bundled' in word
}

function sameSense(a: SenseDraft, b: SenseDraft): boolean {
  return a.pos === b.pos && a.meaning === b.meaning && a.example === b.example && a.exampleJa === b.exampleJa
}

/**
 * 取り込む。全体を 1 つのトランザクションで行い、途中で失敗したら何も書かない。
 * dryRun なら最後まで流してから取り消す（何が起きるかだけを返す）
 */
export function importGroups(
  deps: { db: DB; service: AdminService; bundled: BundledWords },
  input: ImportInput,
  { dryRun = false }: { dryRun?: boolean } = {},
): GroupReport[] {
  const { db, service, bundled } = deps
  let reports: GroupReport[] = []
  const run = db.transaction(() => {
    reports = input.groups.map((groupInput) => importGroup(service, bundled, groupInput))
    if (dryRun) throw new DryRunRollback()
  })
  try {
    run()
  } catch (error) {
    if (!(error instanceof DryRunRollback)) throw error
  }
  return reports
}

function importGroup(
  service: AdminService,
  bundled: BundledWords,
  input: ImportInput['groups'][number],
): GroupReport {
  const name = normalizeGroupName(input.name)
  const sameName = service.listGroups().filter((group) => group.name === name)
  if (sameName.length > 1) throw new ImportInputError(`「${name}」という名前のグループが複数ある`)
  const created = sameName.length === 0
  const groupId = (sameName[0] ?? service.createGroup(name)).id
  const report: GroupReport = { name, created, added: [], alreadyIn: [], customCreated: [], customReplaced: [] }
  const contains = (wordId: string) => service.getGroup(groupId).wordIds.includes(wordId)

  for (const word of input.words) {
    if (isBundledInput(word)) {
      const entry = bundled.get(word.bundled)
      if (!entry) throw new ImportInputError(`「${name}」: 単語帳に ${word.bundled} が無い`)
      if (normalizeSpelling(entry.word) !== normalizeSpelling(word.word)) {
        throw new ImportInputError(`「${name}」: ${word.bundled} は ${entry.word}（${word.word} ではない）`)
      }
      if (contains(word.bundled)) {
        report.alreadyIn.push(word.word)
      } else {
        service.addWords(groupId, [word.bundled])
        report.added.push(word.word)
      }
      continue
    }

    const draft: WordDraft = { ...word, extraSenses: word.extraSenses ?? [] }
    const [existing] = service.customWordsSpelledLike(draft.word)
    const unchanged =
      existing !== undefined &&
      sameSense(existing, draft) &&
      existing.extraSenses.length === draft.extraSenses.length &&
      existing.extraSenses.every((sense, i) => sameSense(sense, draft.extraSenses[i]))
    if (unchanged && contains(existing.wordId)) {
      report.alreadyIn.push(draft.word)
      continue
    }
    let saved
    try {
      saved = unchanged ? existing : service.upsertCustomWord(draft)
    } catch (error) {
      if (error instanceof AdminInputError) throw new ImportInputError(`「${name}」の ${draft.word}: ${error.message}`)
      throw error
    }
    if (existing === undefined) report.customCreated.push(draft.word)
    else if (!unchanged) report.customReplaced.push(draft.word)
    if (contains(saved.wordId)) {
      report.alreadyIn.push(draft.word)
    } else {
      service.addWords(groupId, [saved.wordId])
      report.added.push(draft.word)
    }
  }
  return report
}

/** 結果を人が読む形にする（CLI の出力） */
export function formatReports(reports: GroupReport[], dryRun: boolean): string {
  const lines: string[] = []
  for (const r of reports) {
    lines.push(`${r.created ? '＋ 作る' : '・ 既存'} 「${r.name}」: 足す ${r.added.length} / 入っている ${r.alreadyIn.length}`)
    if (r.customCreated.length > 0) lines.push(`    マイ単語を作る: ${r.customCreated.join(', ')}`)
    if (r.customReplaced.length > 0) lines.push(`    マイ単語の中身を置き換える: ${r.customReplaced.join(', ')}`)
  }
  const sum = (pick: (r: GroupReport) => unknown[] | boolean) =>
    reports.reduce((n, r) => {
      const v = pick(r)
      return n + (typeof v === 'boolean' ? Number(v) : v.length)
    }, 0)
  lines.push(
    `合計: グループを作る ${sum((r) => r.created)} / 語を足す ${sum((r) => r.added)} / ` +
      `マイ単語を作る ${sum((r) => r.customCreated)} / 置き換える ${sum((r) => r.customReplaced)}`,
  )
  if (dryRun) lines.push('（--dry-run なので書き込んでいない）')
  return lines.join('\n')
}
