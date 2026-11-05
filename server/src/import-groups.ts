import { readFileSync } from 'node:fs'
import { formatReports, ImportInputError, importGroups, parseImportInput } from './admin/import-groups.ts'
import { AdminService } from './admin/service.ts'
import { DEFAULT_DB_PATH } from './config.ts'
import { migrate, openDatabase } from './db.ts'
import { SyncStore } from './sync/store.ts'
import { BundledWords } from './words/bundled.ts'

// グループと語を JSON からまとめて取り込む。
//
//   node server/src/import-groups.ts [--dry-run] [file]   （file を省くと標準入力から読む）
//
// 本番（g3plus）では JSON をイメージに入れず、標準入力で渡す:
//   docker compose exec -T vocab-blossom node server/src/import-groups.ts --dry-run < data/groups/connectives.json
//
// DB は VOCAB_DB_PATH（無ければサーバーと同じ既定の場所）。動いているサーバーと同時に書いても、
// WAL と busy_timeout で待つだけで壊れない。

function main(): void {
  const args = process.argv.slice(2)
  const dryRun = args.includes('--dry-run')
  const unknown = args.filter((arg) => arg.startsWith('--') && arg !== '--dry-run')
  const files = args.filter((arg) => !arg.startsWith('--'))
  if (unknown.length > 0 || files.length > 1) {
    console.error('使い方: node server/src/import-groups.ts [--dry-run] [file]')
    process.exit(2)
  }

  const dbPath = process.env.VOCAB_DB_PATH?.trim() || DEFAULT_DB_PATH
  const db = openDatabase(dbPath)
  try {
    const input = parseImportInput(JSON.parse(readFileSync(files[0] ?? 0, 'utf8')))
    migrate(db)
    const bundled = BundledWords.load()
    const service = new AdminService({ db, store: new SyncStore(db), bundled, now: Date.now })
    const reports = importGroups({ db, service, bundled }, input, { dryRun })
    console.log(`db: ${dbPath}`)
    console.log(formatReports(reports, dryRun))
  } catch (error) {
    if (error instanceof ImportInputError || error instanceof SyntaxError) {
      console.error(`取り込めなかった（何も書き込んでいない）: ${error.message}`)
      process.exitCode = 1
    } else {
      throw error
    }
  } finally {
    db.close()
  }
}

main()
