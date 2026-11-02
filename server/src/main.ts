import { createServer } from 'node:http'
import { consoleLogger, createApp } from './app.ts'
import { ConfigError, loadConfig } from './config.ts'
import { migrate, openDatabase } from './db.ts'
import { nodeListener } from './http/adapter.ts'

// 起動: node server/src/main.ts（Node 24 の型除去でそのまま動く。ビルド工程なし）

function main(): void {
  let config
  try {
    config = loadConfig(process.env)
  } catch (error) {
    if (error instanceof ConfigError) {
      console.error(`[config] ${error.message}`)
      process.exit(1)
    }
    throw error
  }

  const db = openDatabase(config.dbPath)
  const applied = migrate(db)
  if (applied > 0) console.log(`[db] マイグレーションを ${applied} 件適用した`)

  const handle = createApp({ config, db, logger: consoleLogger })
  const server = createServer(
    nodeListener(handle, (error) => consoleLogger.error('[http] 応答の書き出しに失敗', error)),
  )

  server.listen(config.port, () => {
    console.log(
      `vocab-blossom server: http://localhost:${config.port}` +
        ` (db: ${config.dbPath}, admin: ${config.adminEnabled ? 'on' : 'off'},` +
        ` ai: ${config.anthropicApiKey ? 'on' : 'off'})`,
    )
  })

  // docker stop の SIGTERM で受付をやめ、DB を閉じて終わる（PID 1 は既定でシグナルを無視するため）
  let closing = false
  const shutdown = (signal: string): void => {
    if (closing) return
    closing = true
    console.log(`[server] ${signal} を受けたので終了する`)
    server.close(() => {
      db.close()
      process.exit(0)
    })
    server.closeIdleConnections()
    setTimeout(() => process.exit(0), 5000).unref()
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'))
  process.on('SIGINT', () => shutdown('SIGINT'))
}

main()
