import type { DB, Migration } from '../db.ts'
import {
  type CustomWord,
  type Deletion,
  type DeletionKind,
  type Group,
  type PartOfSpeech,
  type SyncRequest,
  type SyncResponse,
  type WordSense,
  isCustomWordId,
  uniqueIds,
} from './types.ts'

// グループ・自作語・削除記録の読み書き。端末からの同期（POST /api/sync）と管理画面（Phase 3）の両方が使う。
//
// - レコードを変えるたびに通し番号（rev）を振る。端末は受け取った最後の rev を cursor として覚える
// - ぶつかったら updatedAt / deletedAt の新しい方を採用する。同じ時刻ならサーバーにあるものを残し、削除が勝つ
// - 何も変わらないときは rev を進めない（同じ内容を 2 回送っても壊れない）
// - 生きているレコードと削除記録は同じ ID で同時に存在しない

export const SYNC_MIGRATION: Migration = {
  name: 'sync-tables',
  up: (db) => {
    db.exec(`
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      );
      INSERT INTO sync_meta (key, value) VALUES ('rev', 0);

      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        word_ids TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        rev INTEGER NOT NULL
      );
      CREATE INDEX groups_rev ON groups (rev);

      CREATE TABLE custom_words (
        word_id TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        meaning TEXT NOT NULL,
        pos TEXT NOT NULL,
        example TEXT NOT NULL,
        example_ja TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        rev INTEGER NOT NULL
      );
      CREATE INDEX custom_words_rev ON custom_words (rev);

      CREATE TABLE deletions (
        kind TEXT NOT NULL CHECK (kind IN ('group', 'customWord')),
        id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        rev INTEGER NOT NULL,
        PRIMARY KEY (kind, id)
      );
      CREATE INDEX deletions_rev ON deletions (rev);
    `)
  },
}

/** 自作語に 2 つ目以降の意味（`extraSenses`）を足す。前からある語は空（`[]`）になる */
export const EXTRA_SENSES_MIGRATION: Migration = {
  name: 'custom-words-extra-senses',
  up: (db) => {
    db.exec(`ALTER TABLE custom_words ADD COLUMN extra_senses TEXT NOT NULL DEFAULT '[]'`)
  },
}

/** apply* の結果。ignored はサーバーの方が新しい・同じで何もしなかった */
export type ApplyResult = 'applied' | 'ignored'

type GroupRow = {
  id: string
  name: string
  word_ids: string
  created_at: number
  updated_at: number
  rev: number
}

type CustomWordRow = {
  word_id: string
  word: string
  meaning: string
  pos: string
  example: string
  example_ja: string
  /** `WordSense[]` の JSON */
  extra_senses: string
  created_at: number
  updated_at: number
  rev: number
}

type DeletionRow = {
  kind: DeletionKind
  id: string
  deleted_at: number
  rev: number
}

type WithRev<T> = { record: T; rev: number }

function toGroup(row: GroupRow): Group {
  return {
    id: row.id,
    name: row.name,
    wordIds: JSON.parse(row.word_ids) as string[],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

function toCustomWord(row: CustomWordRow): CustomWord {
  return {
    wordId: row.word_id,
    word: row.word,
    meaning: row.meaning,
    pos: row.pos as PartOfSpeech,
    example: row.example,
    exampleJa: row.example_ja,
    extraSenses: JSON.parse(row.extra_senses) as WordSense[],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

function toDeletion(row: DeletionRow): Deletion {
  return { kind: row.kind, id: row.id, deletedAt: row.deleted_at }
}

function sameIds(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((id, i) => id === b[i])
}

export class SyncStore {
  private readonly db: DB

  constructor(db: DB) {
    this.db = db
  }

  // --- 読む ---

  /** 最後に振った rev（端末に返す cursor） */
  currentRev(): number {
    const row = this.db.prepare("SELECT value FROM sync_meta WHERE key = 'rev'").get() as
      | { value: number }
      | undefined
    return row?.value ?? 0
  }

  getGroup(id: string): Group | null {
    const row = this.db.prepare('SELECT * FROM groups WHERE id = ?').get(id) as GroupRow | undefined
    return row ? toGroup(row) : null
  }

  getCustomWord(wordId: string): CustomWord | null {
    const row = this.db.prepare('SELECT * FROM custom_words WHERE word_id = ?').get(wordId) as
      | CustomWordRow
      | undefined
    return row ? toCustomWord(row) : null
  }

  getDeletion(kind: DeletionKind, id: string): Deletion | null {
    const row = this.db.prepare('SELECT * FROM deletions WHERE kind = ? AND id = ?').get(kind, id) as
      | DeletionRow
      | undefined
    return row ? toDeletion(row) : null
  }

  /** 更新日時の新しい順 */
  listGroups(): Group[] {
    const rows = this.db.prepare('SELECT * FROM groups ORDER BY updated_at DESC, id').all() as GroupRow[]
    return rows.map(toGroup)
  }

  /** 作った日時の新しい順 */
  listCustomWords(): CustomWord[] {
    const rows = this.db
      .prepare('SELECT * FROM custom_words ORDER BY created_at DESC, word_id')
      .all() as CustomWordRow[]
    return rows.map(toCustomWord)
  }

  // --- 書く（LWW） ---

  /** グループを作る・置き換える。削除記録のある自作語の ID は抜いて保存する */
  applyGroup(incoming: Group): ApplyResult {
    return this.db.transaction((): ApplyResult => {
      const deletion = this.getDeletion('group', incoming.id)
      if (deletion && deletion.deletedAt >= incoming.updatedAt) return 'ignored'
      const existing = this.getGroup(incoming.id)
      if (existing && existing.updatedAt >= incoming.updatedAt) return 'ignored'

      const wordIds = uniqueIds(incoming.wordIds).filter(
        (id) => !(isCustomWordId(id) && this.isDeletedCustomWord(id)),
      )
      this.writeGroup({ ...incoming, wordIds }, this.nextRev())
      if (deletion) this.removeDeletion('group', incoming.id)
      return 'applied'
    })()
  }

  /** 自作語を作る・置き換える */
  applyCustomWord(incoming: CustomWord): ApplyResult {
    return this.db.transaction((): ApplyResult => {
      const deletion = this.getDeletion('customWord', incoming.wordId)
      if (deletion && deletion.deletedAt >= incoming.updatedAt) return 'ignored'
      const existing = this.getCustomWord(incoming.wordId)
      if (existing && existing.updatedAt >= incoming.updatedAt) return 'ignored'

      this.db
        .prepare(
          `INSERT INTO custom_words
             (word_id, word, meaning, pos, example, example_ja, extra_senses,
              created_at, updated_at, rev)
           VALUES (@wordId, @word, @meaning, @pos, @example, @exampleJa, @extraSenses,
                   @createdAt, @updatedAt, @rev)
           ON CONFLICT (word_id) DO UPDATE SET
             word = excluded.word, meaning = excluded.meaning, pos = excluded.pos,
             example = excluded.example, example_ja = excluded.example_ja,
             extra_senses = excluded.extra_senses,
             created_at = excluded.created_at, updated_at = excluded.updated_at, rev = excluded.rev`,
        )
        .run({ ...incoming, extraSenses: JSON.stringify(incoming.extraSenses), rev: this.nextRev() })
      if (deletion) this.removeDeletion('customWord', incoming.wordId)
      return 'applied'
    })()
  }

  /**
   * 削除を当てる。サーバーのレコードの方が新しければ捨てる。
   * 自作語の削除は、その語を含むグループからも ID を抜く（グループの updatedAt は deletedAt まで進める）
   */
  applyDeletion(incoming: Deletion): ApplyResult {
    return this.db.transaction((): ApplyResult => {
      const existing = this.getDeletion(incoming.kind, incoming.id)
      if (existing && existing.deletedAt >= incoming.deletedAt) return 'ignored'

      if (incoming.kind === 'group') {
        const group = this.getGroup(incoming.id)
        if (group && group.updatedAt > incoming.deletedAt) return 'ignored'
        this.db.prepare('DELETE FROM groups WHERE id = ?').run(incoming.id)
      } else {
        const word = this.getCustomWord(incoming.id)
        if (word && word.updatedAt > incoming.deletedAt) return 'ignored'
        this.db.prepare('DELETE FROM custom_words WHERE word_id = ?').run(incoming.id)
      }

      this.db
        .prepare(
          `INSERT INTO deletions (kind, id, deleted_at, rev) VALUES (@kind, @id, @deletedAt, @rev)
           ON CONFLICT (kind, id) DO UPDATE SET deleted_at = excluded.deleted_at, rev = excluded.rev`,
        )
        .run({ ...incoming, rev: this.nextRev() })

      if (incoming.kind === 'customWord') this.removeFromGroups(incoming.id, incoming.deletedAt)
      return 'applied'
    })()
  }

  // --- 同期 ---

  /**
   * 端末の変更を 1 トランザクションで当て、cursor より後の変更と、送られてきたレコードのサーバーでの今の状態を返す。
   * 自作語 → グループ → 削除の順に当てる
   */
  sync(request: SyncRequest): SyncResponse {
    return this.db.transaction((): SyncResponse => {
      // サーバーの DB が作り直されて端末の cursor の方が進んでいたら、全件を返す
      const reset = request.cursor > this.currentRev()
      const cursor = reset ? 0 : request.cursor

      for (const word of request.customWords) this.applyCustomWord(word)
      for (const group of request.groups) this.applyGroup(group)
      for (const deletion of request.deletions) this.applyDeletion(deletion)

      const groups = new Map<string, WithRev<Group>>()
      const customWords = new Map<string, WithRev<CustomWord>>()
      const deletions = new Map<string, WithRev<Deletion>>()
      const deletionKey = (kind: DeletionKind, id: string) => `${kind}:${id}`

      for (const row of this.db
        .prepare('SELECT * FROM groups WHERE rev > ?')
        .all(cursor) as GroupRow[]) {
        groups.set(row.id, { record: toGroup(row), rev: row.rev })
      }
      for (const row of this.db
        .prepare('SELECT * FROM custom_words WHERE rev > ?')
        .all(cursor) as CustomWordRow[]) {
        customWords.set(row.word_id, { record: toCustomWord(row), rev: row.rev })
      }
      for (const row of this.db
        .prepare('SELECT * FROM deletions WHERE rev > ?')
        .all(cursor) as DeletionRow[]) {
        deletions.set(deletionKey(row.kind, row.id), { record: toDeletion(row), rev: row.rev })
      }

      // 送られてきたものは、採用しなかった場合もサーバーの値で端末を上書きできるよう今の状態を返す
      const addCurrent = (kind: DeletionKind, id: string) => {
        if (kind === 'group') {
          const row = this.db.prepare('SELECT * FROM groups WHERE id = ?').get(id) as GroupRow | undefined
          if (row) groups.set(id, { record: toGroup(row), rev: row.rev })
        } else {
          const row = this.db.prepare('SELECT * FROM custom_words WHERE word_id = ?').get(id) as
            | CustomWordRow
            | undefined
          if (row) customWords.set(id, { record: toCustomWord(row), rev: row.rev })
        }
        const row = this.db
          .prepare('SELECT * FROM deletions WHERE kind = ? AND id = ?')
          .get(kind, id) as DeletionRow | undefined
        if (row) deletions.set(deletionKey(kind, id), { record: toDeletion(row), rev: row.rev })
      }
      for (const group of request.groups) addCurrent('group', group.id)
      for (const word of request.customWords) addCurrent('customWord', word.wordId)
      for (const deletion of request.deletions) addCurrent(deletion.kind, deletion.id)

      const byRev = <T>(map: Map<string, WithRev<T>>): T[] =>
        [...map.values()].sort((a, b) => a.rev - b.rev).map((v) => v.record)

      return {
        cursor: this.currentRev(),
        reset,
        groups: byRev(groups),
        customWords: byRev(customWords),
        deletions: byRev(deletions),
      }
    })()
  }

  // --- 内部 ---

  private nextRev(): number {
    const row = this.db
      .prepare("UPDATE sync_meta SET value = value + 1 WHERE key = 'rev' RETURNING value")
      .get() as { value: number }
    return row.value
  }

  private writeGroup(group: Group, rev: number): void {
    this.db
      .prepare(
        `INSERT INTO groups (id, name, word_ids, created_at, updated_at, rev)
         VALUES (@id, @name, @wordIds, @createdAt, @updatedAt, @rev)
         ON CONFLICT (id) DO UPDATE SET
           name = excluded.name, word_ids = excluded.word_ids,
           created_at = excluded.created_at, updated_at = excluded.updated_at, rev = excluded.rev`,
      )
      .run({ ...group, wordIds: JSON.stringify(group.wordIds), rev })
  }

  private removeDeletion(kind: DeletionKind, id: string): void {
    this.db.prepare('DELETE FROM deletions WHERE kind = ? AND id = ?').run(kind, id)
  }

  /** 自作語が消されている（作り直されたら削除記録は消えるので、記録があれば今も消えている） */
  private isDeletedCustomWord(wordId: string): boolean {
    return this.getDeletion('customWord', wordId) !== null
  }

  private removeFromGroups(wordId: string, deletedAt: number): void {
    const rows = this.db
      .prepare(
        `SELECT * FROM groups
         WHERE EXISTS (SELECT 1 FROM json_each(groups.word_ids) WHERE json_each.value = ?)`,
      )
      .all(wordId) as GroupRow[]
    for (const row of rows) {
      const group = toGroup(row)
      const wordIds = group.wordIds.filter((id) => id !== wordId)
      if (sameIds(wordIds, group.wordIds)) continue
      this.writeGroup(
        { ...group, wordIds, updatedAt: Math.max(group.updatedAt, deletedAt) },
        this.nextRev(),
      )
    }
  }
}
