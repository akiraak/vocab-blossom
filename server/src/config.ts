import path from 'node:path'

// サーバーの設定は起動時の環境変数だけで決める（デプロイ契約: docs/specs/deploy-g3plus.md）

export type Config = {
  port: number
  /** iOS の /api/* を守る共有シークレット（必須） */
  apiSharedSecret: string
  /** ADMIN_ENABLED=on のときだけ /admin/* を有効にする（未設定は 404 = fail-safe） */
  adminEnabled: boolean
  dbPath: string
  /** 未設定なら AI 機能だけ使えない */
  anthropicApiKey: string | undefined
  /** 自作語の AI チェックに使うモデル（未設定なら ai/claude.ts の既定） */
  anthropicModel: string | undefined
}

export const DEFAULT_PORT = 3015
export const DEFAULT_DB_PATH = path.resolve(import.meta.dirname, '../data/vocab-blossom.db')

export class ConfigError extends Error {}

export function loadConfig(env: Record<string, string | undefined>): Config {
  const apiSharedSecret = env.API_SHARED_SECRET?.trim() ?? ''
  if (apiSharedSecret === '') {
    throw new ConfigError('API_SHARED_SECRET が設定されていません（openssl rand -hex 32 で作る）')
  }

  const portText = env.PORT?.trim()
  const port = portText ? Number(portText) : DEFAULT_PORT
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new ConfigError(`PORT が不正です: ${portText}`)
  }

  return {
    port,
    apiSharedSecret,
    adminEnabled: env.ADMIN_ENABLED?.trim() === 'on',
    dbPath: env.VOCAB_DB_PATH?.trim() || DEFAULT_DB_PATH,
    anthropicApiKey: env.ANTHROPIC_API_KEY?.trim() || undefined,
    anthropicModel: env.ANTHROPIC_MODEL?.trim() || undefined,
  }
}
