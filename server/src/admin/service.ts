import { randomUUID } from 'node:crypto'
import type { DB } from '../db.ts'
import type { SyncStore } from '../sync/store.ts'
import {
  CUSTOM_WORD_PREFIX,
  type CustomWord,
  type Group,
  LIMITS,
  PARTS_OF_SPEECH,
  type PartOfSpeech,
  type WordSense,
  isCustomWordId,
} from '../sync/types.ts'
import { type BundledWords, normalizeSpelling } from '../words/bundled.ts'

// 管理画面の操作。書き込みは同期と同じ SyncStore の apply* を通す（rev が振られ、端末に届く）。
//
// 日時は max(今, 今の updatedAt + 1)。端末の時計が進んでいて、そちらの updatedAt の方が新しいと
// LWW で管理画面の変更が捨てられてしまうため、必ず今の値より新しくする。

export const DEFAULT_GROUP_NAME = '新しいグループ'

/** 画面に出す入力の誤り */
export class AdminInputError extends Error {}

/** 対象が見つからない（404） */
export class AdminNotFoundError extends Error {}

/** フォームの意味 1 つ分（品詞は検証前なので文字列） */
export type SenseDraft = {
  meaning: string
  pos: string
  example: string
  exampleJa: string
}

/** フォームの中身。meaning・pos・example・exampleJa は 1 つ目の意味、2 つ目以降は extraSenses */
export type WordDraft = SenseDraft & {
  word: string
  extraSenses: SenseDraft[]
}

export type ValidDraft = Omit<WordDraft, 'pos' | 'extraSenses'> & { pos: PartOfSpeech; extraSenses: WordSense[] }

/** グループの中の 1 語。解決できない ID は kind: 'unknown' */
export type GroupEntry =
  | { kind: 'bundled'; id: string; word: string; meaning: string; pos: PartOfSpeech; level: string }
  | { kind: 'custom'; id: string; word: string; meaning: string; pos: PartOfSpeech; extraSenses: WordSense[] }
  | { kind: 'unknown'; id: string }

export type MoveDirection = 'up' | 'down'

/** iOS の GroupEditor.normalizedName と同じ（空なら「新しいグループ」） */
export function normalizeGroupName(name: string): string {
  const trimmed = name.trim()
  return trimmed === '' ? DEFAULT_GROUP_NAME : trimmed
}

/** 意味の欄がすべて空（足すための空の欄・消した欄）。品詞は選んであっても見ない */
export function isBlankSense(sense: SenseDraft): boolean {
  return sense.meaning.trim() === '' && sense.example.trim() === '' && sense.exampleJa.trim() === ''
}

/** 意味 1 つ分を検証する。number は 2 つ目以降の意味の番号（エラーに「意味 2 の」と添える） */
function validateSense(sense: SenseDraft, number?: number): WordSense {
  const prefix = number === undefined ? '' : `意味 ${number} の`
  const value = {
    meaning: sense.meaning.trim(),
    pos: sense.pos.trim(),
    example: sense.example.trim(),
    exampleJa: sense.exampleJa.trim(),
  }
  if (value.meaning === '') throw new AdminInputError(`${prefix}意味を入れてください`)
  if (!(PARTS_OF_SPEECH as readonly string[]).includes(value.pos)) {
    throw new AdminInputError(`${prefix}品詞を選んでください`)
  }
  if (value.meaning.length > LIMITS.meaning) {
    throw new AdminInputError(`${prefix}意味は ${LIMITS.meaning} 文字までです`)
  }
  if (value.example.length > LIMITS.example || value.exampleJa.length > LIMITS.example) {
    throw new AdminInputError(`${prefix}例文・例文の訳は ${LIMITS.example} 文字までです`)
  }
  return { ...value, pos: value.pos as PartOfSpeech }
}

export function validateDraft(draft: WordDraft): ValidDraft {
  const word = draft.word.trim()
  if (word === '') throw new AdminInputError('英語を入れてください')
  if (word.length > LIMITS.word) throw new AdminInputError(`英語は ${LIMITS.word} 文字までです`)
  const primary = validateSense(draft)
  // 2 つ目以降は、欄がすべて空なら無いものとする（足すための空の欄・消した欄）
  const extras = draft.extraSenses.filter((sense) => !isBlankSense(sense))
  if (extras.length > LIMITS.extraSenses) {
    throw new AdminInputError(`意味は ${LIMITS.extraSenses + 1} 個までです`)
  }
  const extraSenses = extras.map((sense, i) => validateSense(sense, i + 2))
  return { word, ...primary, extraSenses }
}

export class AdminService {
  private readonly db: DB
  private readonly store: SyncStore
  private readonly bundled: BundledWords
  private readonly now: () => number

  constructor(deps: { db: DB; store: SyncStore; bundled: BundledWords; now: () => number }) {
    this.db = deps.db
    this.store = deps.store
    this.bundled = deps.bundled
    this.now = deps.now
  }

  // --- 読む ---

  listGroups(): Group[] {
    return this.store.listGroups()
  }

  listCustomWords(): CustomWord[] {
    return this.store.listCustomWords()
  }

  getGroup(id: string): Group {
    const group = this.store.getGroup(id.toLowerCase())
    if (!group) throw new AdminNotFoundError('グループが見つかりません')
    return group
  }

  getCustomWord(wordId: string): CustomWord {
    const word = isCustomWordId(wordId) ? this.store.getCustomWord(wordId) : null
    if (!word) throw new AdminNotFoundError('単語が見つかりません')
    return word
  }

  /** グループの語を並びどおりに解決する */
  entries(group: Group): GroupEntry[] {
    return group.wordIds.map((id): GroupEntry => {
      const bundled = this.bundled.get(id)
      if (bundled) {
        const { word, meaning, pos, level } = bundled
        return { kind: 'bundled', id, word, meaning, pos, level }
      }
      const custom = isCustomWordId(id) ? this.store.getCustomWord(id) : null
      if (custom) {
        const { word, meaning, pos, extraSenses } = custom
        return { kind: 'custom', id, word, meaning, pos, extraSenses }
      }
      return { kind: 'unknown', id }
    })
  }

  /** 同じ綴り（大小文字・前後の空白は無視）の自作語。新しく更新した順 */
  customWordsSpelledLike(word: string): CustomWord[] {
    const spelling = normalizeSpelling(word)
    if (spelling === '') return []
    return this.store
      .listCustomWords()
      .filter((w) => normalizeSpelling(w.word) === spelling)
      .sort((a, b) => b.updatedAt - a.updatedAt)
  }

  /** 自作語ごとに、入っているグループ */
  groupsByCustomWord(): Map<string, Group[]> {
    const map = new Map<string, Group[]>()
    for (const group of this.store.listGroups()) {
      for (const id of group.wordIds) {
        if (!isCustomWordId(id)) continue
        const list = map.get(id) ?? []
        list.push(group)
        map.set(id, list)
      }
    }
    return map
  }

  // --- グループ ---

  createGroup(name: string): Group {
    const t = this.now()
    const group: Group = {
      id: randomUUID().toLowerCase(),
      name: this.checkedName(name),
      wordIds: [],
      createdAt: t,
      updatedAt: t,
    }
    this.store.applyGroup(group)
    return group
  }

  renameGroup(id: string, name: string): void {
    const checked = this.checkedName(name)
    this.updateGroup(id, (group) => (group.name === checked ? null : { ...group, name: checked }))
  }

  deleteGroup(id: string): void {
    this.db.transaction(() => {
      const group = this.getGroup(id)
      this.store.applyDeletion({
        kind: 'group',
        id: group.id,
        deletedAt: Math.max(this.now(), group.updatedAt + 1),
      })
    })()
  }

  /** 末尾に足す。入っている語は飛ばす（順番も動かさない） */
  addWords(groupId: string, wordIds: string[]): void {
    for (const wordId of wordIds) {
      if (!this.wordExists(wordId)) throw new AdminInputError(`追加できない単語です: ${wordId}`)
    }
    this.updateGroup(groupId, (group) => {
      const additions = wordIds.filter((id) => !group.wordIds.includes(id))
      return additions.length === 0 ? null : { ...group, wordIds: [...group.wordIds, ...additions] }
    })
  }

  removeWord(groupId: string, wordId: string): void {
    this.updateGroup(groupId, (group) =>
      group.wordIds.includes(wordId)
        ? { ...group, wordIds: group.wordIds.filter((id) => id !== wordId) }
        : null,
    )
  }

  moveWord(groupId: string, wordId: string, direction: MoveDirection): void {
    this.updateGroup(groupId, (group) => {
      const from = group.wordIds.indexOf(wordId)
      const to = direction === 'up' ? from - 1 : from + 1
      if (from < 0 || to < 0 || to >= group.wordIds.length) return null
      const wordIds = [...group.wordIds]
      ;[wordIds[from], wordIds[to]] = [wordIds[to], wordIds[from]]
      return { ...group, wordIds }
    })
  }

  // --- 自作語 ---

  /** 自作語を作る。groupId を渡すとそのグループの末尾にも入れる */
  createCustomWord(draft: WordDraft, groupId?: string): CustomWord {
    const value = validateDraft(draft)
    return this.db.transaction((): CustomWord => {
      if (groupId !== undefined) this.getGroup(groupId)
      const t = this.now()
      const word: CustomWord = {
        wordId: CUSTOM_WORD_PREFIX + randomUUID().toLowerCase(),
        ...value,
        createdAt: t,
        updatedAt: t,
      }
      this.store.applyCustomWord(word)
      if (groupId !== undefined) this.addWords(groupId, [word.wordId])
      return word
    })()
  }

  /**
   * 自作語を作る。同じ綴りの自作語は 1 つだけにする（iOS の GroupEditor.upsertCustomWord と同じ）。
   *
   * 同じ綴りが無ければ作る。あればいちばん新しく更新したものの内容を置き換え（ID はそのまま。アプリの学習の記録が残る）、
   * ほかの同じ綴りの自作語は、グループでの位置を寄せる先に引き継いでから削除記録を残して消す。
   * groupId を渡すとそのグループの末尾にも入れる（すでに入っていれば位置は動かさない）
   */
  upsertCustomWord(draft: WordDraft, groupId?: string): CustomWord {
    const value = validateDraft(draft)
    return this.db.transaction((): CustomWord => {
      if (groupId !== undefined) this.getGroup(groupId)
      const [kept, ...duplicates] = this.customWordsSpelledLike(value.word)
      if (!kept) return this.createCustomWord(draft, groupId)
      for (const duplicate of duplicates) {
        for (const group of this.store.listGroups()) {
          if (!group.wordIds.includes(duplicate.wordId)) continue
          this.updateGroup(group.id, (current) => ({
            ...current,
            wordIds: current.wordIds.includes(kept.wordId)
              ? current.wordIds.filter((id) => id !== duplicate.wordId)
              : current.wordIds.map((id) => (id === duplicate.wordId ? kept.wordId : id)),
          }))
        }
        this.store.applyDeletion({
          kind: 'customWord',
          id: duplicate.wordId,
          deletedAt: Math.max(this.now(), duplicate.updatedAt + 1),
        })
      }
      const word: CustomWord = { ...kept, ...value, updatedAt: Math.max(this.now(), kept.updatedAt + 1) }
      this.store.applyCustomWord(word)
      if (groupId !== undefined) this.addWords(groupId, [word.wordId])
      return word
    })()
  }

  updateCustomWord(wordId: string, draft: WordDraft): void {
    const value = validateDraft(draft)
    this.db.transaction(() => {
      const current = this.getCustomWord(wordId)
      this.store.applyCustomWord({
        ...current,
        ...value,
        updatedAt: Math.max(this.now(), current.updatedAt + 1),
      })
    })()
  }

  /** 自作語を消す。すべてのグループから外れる（SyncStore.applyDeletion が外す） */
  deleteCustomWord(wordId: string): void {
    this.db.transaction(() => {
      const current = this.getCustomWord(wordId)
      this.store.applyDeletion({
        kind: 'customWord',
        id: current.wordId,
        deletedAt: Math.max(this.now(), current.updatedAt + 1),
      })
    })()
  }

  // --- 内部 ---

  private checkedName(name: string): string {
    const normalized = normalizeGroupName(name)
    if (normalized.length > LIMITS.groupName) {
      throw new AdminInputError(`グループ名は ${LIMITS.groupName} 文字までです`)
    }
    return normalized
  }

  private wordExists(wordId: string): boolean {
    if (this.bundled.has(wordId)) return true
    return isCustomWordId(wordId) && this.store.getCustomWord(wordId) !== null
  }

  /** change が null を返したら何もしない（rev も日時も進めない） */
  private updateGroup(id: string, change: (group: Group) => Group | null): void {
    this.db.transaction(() => {
      const group = this.getGroup(id)
      const next = change(group)
      if (next === null) return
      this.store.applyGroup({ ...next, updatedAt: Math.max(this.now(), group.updatedAt + 1) })
    })()
  }
}
