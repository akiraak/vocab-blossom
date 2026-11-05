import { describe, expect, it } from 'vitest'
import { ConfigError, DEFAULT_DB_PATH, DEFAULT_PORT, loadConfig } from './config.ts'

describe('loadConfig', () => {
  it('API_SHARED_SECRET が無ければ起動しない', () => {
    expect(() => loadConfig({})).toThrow(ConfigError)
    expect(() => loadConfig({ API_SHARED_SECRET: '  ' })).toThrow(ConfigError)
  })

  it('既定値', () => {
    expect(loadConfig({ API_SHARED_SECRET: 's' })).toEqual({
      port: DEFAULT_PORT,
      apiSharedSecret: 's',
      adminEnabled: false,
      dbPath: DEFAULT_DB_PATH,
      anthropicApiKey: undefined,
    })
  })

  it('ADMIN_ENABLED は on のときだけ有効', () => {
    const admin = (value: string) =>
      loadConfig({ API_SHARED_SECRET: 's', ADMIN_ENABLED: value }).adminEnabled
    expect(admin('on')).toBe(true)
    expect(admin('true')).toBe(false)
    expect(admin('1')).toBe(false)
    expect(admin('')).toBe(false)
  })

  it('env を読む', () => {
    const config = loadConfig({
      API_SHARED_SECRET: 's',
      PORT: '4000',
      VOCAB_DB_PATH: '/app/server/data/vocab-blossom.db',
      ANTHROPIC_API_KEY: 'sk-ant',
      GEMINI_API_KEY: ' gm-key ',
      GEMINI_TTS_MODEL: 'gemini-3.8-flash-lite-tts',
    })
    expect(config.port).toBe(4000)
    expect(config.dbPath).toBe('/app/server/data/vocab-blossom.db')
    expect(config.anthropicApiKey).toBe('sk-ant')
    expect(config.geminiApiKey).toBe('gm-key')
    expect(config.geminiTtsModel).toBe('gemini-3.8-flash-lite-tts')
  })

  it('PORT が不正なら起動しない', () => {
    expect(() => loadConfig({ API_SHARED_SECRET: 's', PORT: 'abc' })).toThrow(ConfigError)
    expect(() => loadConfig({ API_SHARED_SECRET: 's', PORT: '70000' })).toThrow(ConfigError)
  })
})
