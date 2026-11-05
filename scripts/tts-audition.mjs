// グループの読み上げの声を聞き比べる（docs/plans/read-aloud-gemini-voice.md の Phase 1）。
//
// Gemini TTS を直接呼んで、単語帳の語を「単語 → 意味 → 例文 → 例文の和訳」で読ませ、
// モデル × キャラ × 前置文ごとに WAV を作る。1 語ぶんをつないだ WAV（読み上げと同じ間）も作る。
//
// 使い方（キーは git 管理外の .env.local に GEMINI_API_KEY=... と書いておく。見本は .env.example）:
//   node --env-file=.env.local scripts/tts-audition.mjs
//   node --env-file=.env.local scripts/tts-audition.mjs --models gemini-3.8-flash-tts --chars chobi --styles readaloud,original --words a1-0002,ph-0012
//   マイ単語など単語帳に無い語は --extra <json>（{ "words": [{ id, word, meaning, example, exampleJa }] }）で足し、--words で id を指定する
//
// 出力は tts-audition.local/（git 管理外）。summary.tsv に秒数と英語の話速（words/sec）を出す。

import fs from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(import.meta.dirname, '..')

// MARK: - 条件

const MODELS = ['gemini-3.8-flash-tts', 'gemini-3.8-flash-lite-tts', 'gemini-3.1-flash-tts-preview']

/**
 * キャラの声とスタイル。
 * - original: esl-speaking-coach の ChatCharacter.speechStyle（3.1 向けの長い前置文）
 * - readaloud: 読み上げ用に短くした案（3.8 は「style は短く。年齢・性別・名前は書かない」が推奨）
 * - plain: style なし（公式の推奨は「まず style なしで試す」）
 */
const CHARACTERS = {
  chobi: {
    voice: 'Leda',
    styles: {
      original: {
        all: 'Read aloud in a warm, lively, gently cheerful voice, like a friendly teacher chatting with a student. Speak at a brisk, natural conversational pace, without dragging out words:',
      },
      readaloud: {
        word: 'warm and clear, like a friendly teacher, speaking slowly',
        example: 'warm and friendly, like a teacher reading to a beginner, calm natural pace',
        japanese: 'warm and friendly, like a teacher explaining, calm natural pace',
      },
      plain: { all: '' },
    },
  },
  naruko: {
    voice: 'Aoede',
    styles: {
      original: {
        all: 'Read aloud in a bright, energetic voice, full of curiosity, like an enthusiastic student chatting with friends:',
      },
      readaloud: {
        word: 'bright and cheerful, clear, speaking slowly',
        example: 'bright and cheerful, like a classmate reading to a friend, calm natural pace',
        japanese: 'bright and cheerful, like a classmate explaining to a friend, calm natural pace',
      },
      plain: { all: '' },
    },
  },
}

const DEFAULT_WORDS = ['a1-0002', 'ph-0012', 'a2-0014']

/** 読み上げと同じ間（ReadAloudSpeechEngine の lineGap / itemGap） */
const LINE_GAP_SEC = 0.25

// MARK: - 引数

function parseArgs(argv) {
  const args = {
    models: ['gemini-3.8-flash-tts', 'gemini-3.8-flash-lite-tts'],
    chars: ['chobi', 'naruko'],
    styles: ['readaloud'],
    words: DEFAULT_WORDS,
    extra: null,
    out: path.join(ROOT, 'tts-audition.local'),
  }
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]?.replace(/^--/, '')
    const value = argv[i + 1]
    if (!(key in args) || value === undefined) throw new Error(`不明な引数: ${argv[i]}`)
    args[key] = key === 'out' || key === 'extra' ? path.resolve(value) : value.split(',').map((s) => s.trim()).filter(Boolean)
  }
  for (const m of args.models) if (!MODELS.includes(m)) console.warn(`知らないモデル（そのまま試す）: ${m}`)
  for (const c of args.chars) if (!CHARACTERS[c]) throw new Error(`知らないキャラ: ${c}`)
  for (const s of args.styles) if (!['original', 'readaloud', 'plain'].includes(s)) throw new Error(`知らない前置文: ${s}`)
  return args
}

// MARK: - 読む文（ReadAloudScript と同じ並び・同じ日本語の整え方）

function loadWords(ids, extraFile) {
  const decks = fs.readdirSync(path.join(ROOT, 'data/decks')).filter((f) => f.endsWith('.json'))
  const all = new Map()
  for (const f of decks) {
    for (const w of JSON.parse(fs.readFileSync(path.join(ROOT, 'data/decks', f), 'utf8')).words) all.set(w.id, w)
  }
  if (extraFile) {
    for (const w of JSON.parse(fs.readFileSync(extraFile, 'utf8')).words) all.set(w.id, w)
  }
  return ids.map((id) => {
    const w = all.get(id)
    if (!w) throw new Error(`単語帳に無い id: ${id}`)
    return w
  })
}

function spokenJapanese(text) {
  return text
    .replace(/［[^］]*］/g, '')
    .replaceAll('／', '、')
    .replace(/[〜～]/g, '')
    .trim()
}

function linesFor(word) {
  return [
    { kind: 'word', text: word.word },
    { kind: 'meaning', text: spokenJapanese(word.meaning) },
    { kind: 'example', text: word.example },
    { kind: 'exampleJa', text: spokenJapanese(word.exampleJa) },
  ].filter((l) => l.text)
}

function styleFor(char, styleName, kind) {
  const style = CHARACTERS[char].styles[styleName]
  if (style.all !== undefined) return style.all
  if (kind === 'word') return style.word
  if (kind === 'example') return style.example
  return style.japanese
}

// MARK: - Gemini

/**
 * 3.8 は Interactions API（style を本文と分けて渡す。本文に前置文を混ぜるとそのまま読まれる）。
 * 3.1 は esl-speaking-coach と同じ generateContent（本文の頭に前置文）
 */
async function synthesize({ apiKey, model, voice, style, text }) {
  const legacy = model.startsWith('gemini-3.1') || model.startsWith('gemini-2.5')
  const url = legacy
    ? `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`
    : 'https://generativelanguage.googleapis.com/v1beta/interactions'
  const content = { type: 'text', text }
  if (style) content.annotations = [{ type: 'speech_metadata', style }]
  const body = legacy
    ? {
        contents: [{ parts: [{ text: style ? `${style}\n${text}` : text }] }],
        generationConfig: {
          responseModalities: ['AUDIO'],
          speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } },
        },
      }
    : {
        model,
        input: [{ type: 'user_input', content: [content] }],
        response_format: { type: 'audio', mime_type: 'audio/l16', sample_rate: 24000 },
        generation_config: { speech_config: [{ voice }] },
      }
  for (let attempt = 1; ; attempt++) {
    const started = Date.now()
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify(body),
    })
    const latencyMs = Date.now() - started
    if ((res.status === 429 || res.status === 503) && attempt < 5) {
      const wait = 15 * attempt
      const detail = await res.text().catch(() => '')
      console.warn(`  ${res.status}（混雑・上限）。${wait} 秒待って再試行: ${detail.replace(/\s+/g, ' ').slice(0, 300)}`)
      await new Promise((r) => setTimeout(r, wait * 1000))
      continue
    }
    const json = await res.json().catch(() => null)
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${JSON.stringify(json?.error ?? json).slice(0, 400)}`)
    const audio = legacy
      ? (json?.candidates?.[0]?.content?.parts ?? []).map((p) => p.inlineData).filter((d) => d?.data)
      : (json?.steps ?? [])
          .filter((step) => step.type === 'model_output')
          .flatMap((step) => step.content ?? [])
          .filter((c) => c.type === 'audio' && c.data)
          .map((c) => ({ data: c.data, mimeType: c.mime_type ?? c.mimeType }))
    if (audio.length === 0) throw new Error(`音声が返らなかった: ${JSON.stringify(json).slice(0, 600)}`)
    const mimeType = audio[0].mimeType ?? ''
    const rate = Number(/rate=(\d+)/.exec(mimeType)?.[1] ?? 24000)
    const pcm = stripWavHeader(Buffer.concat(audio.map((a) => Buffer.from(a.data, 'base64'))))
    const usage = legacy ? json.usageMetadata : json.usage
    return { pcm, rate, mimeType, latencyMs, usage, outTokens: outputTokens(usage) }
  }
}

/** WAV で返ってきたら data チャンクの中身だけにする */
function stripWavHeader(buffer) {
  if (buffer.subarray(0, 4).toString('ascii') !== 'RIFF') return buffer
  const index = buffer.indexOf('data', 12, 'ascii')
  return index < 0 ? buffer.subarray(44) : buffer.subarray(index + 8)
}

/** 出力トークン（API によって名前が違うので、それらしいものを拾う） */
function outputTokens(usage) {
  if (!usage) return ''
  return usage.candidatesTokenCount ?? usage.total_output_tokens ?? usage.output_tokens ?? ''
}

// MARK: - 音声

function wav(pcm, rate) {
  const header = Buffer.alloc(44)
  header.write('RIFF', 0)
  header.writeUInt32LE(36 + pcm.length, 4)
  header.write('WAVEfmt ', 8)
  header.writeUInt32LE(16, 16)
  header.writeUInt16LE(1, 20) // PCM
  header.writeUInt16LE(1, 22) // mono
  header.writeUInt32LE(rate, 24)
  header.writeUInt32LE(rate * 2, 28)
  header.writeUInt16LE(2, 32)
  header.writeUInt16LE(16, 34)
  header.write('data', 36)
  header.writeUInt32LE(pcm.length, 40)
  return Buffer.concat([header, pcm])
}

/** 前後の無音を除いた発話区間の秒数（10ms 窓で振幅 500 を超えたところ） */
function speechSeconds(pcm, rate) {
  const window = Math.floor(rate / 100)
  const samples = pcm.length / 2
  const loud = []
  for (let start = 0; start + window <= samples; start += window) {
    let peak = 0
    for (let i = start; i < start + window; i++) peak = Math.max(peak, Math.abs(pcm.readInt16LE(i * 2)))
    loud.push(peak > 500)
  }
  const first = loud.indexOf(true)
  const last = loud.lastIndexOf(true)
  return first < 0 ? 0 : (last - first + 1) / 100
}

const silence = (sec, rate) => Buffer.alloc(Math.round(sec * rate) * 2)

// MARK: - main

async function main() {
  const apiKey = process.env.GEMINI_API_KEY?.trim()
  if (!apiKey) throw new Error('GEMINI_API_KEY がありません（.env.local に書いて --env-file=.env.local で起動する）')
  const args = parseArgs(process.argv.slice(2))
  const words = loadWords(args.words, args.extra)
  fs.mkdirSync(args.out, { recursive: true })

  const rows = [['model', 'char', 'style', 'word', 'kind', 'text', 'total_sec', 'speech_sec', 'words_per_sec', 'latency_ms', 'out_tokens', 'file']]
  let failures = 0
  // 途中で止まっても結果が残るよう、1 本ごとに書き出す
  const writeSummary = () => fs.writeFileSync(path.join(args.out, 'summary.tsv'), rows.map((r) => r.join('\t')).join('\n') + '\n')
  for (const model of args.models) {
    for (const char of args.chars) {
      for (const styleName of args.styles) {
        const dir = path.join(args.out, model, `${char}-${styleName}`)
        fs.mkdirSync(dir, { recursive: true })
        for (const word of words) {
          const pieces = []
          let rate = 24000
          for (const line of linesFor(word)) {
            const label = `${model} / ${char} / ${styleName} / ${word.word} / ${line.kind}`
            try {
              const result = await synthesize({
                apiKey, model, voice: CHARACTERS[char].voice, style: styleFor(char, styleName, line.kind), text: line.text,
              })
              rate = result.rate
              const file = path.join(dir, `${word.id}-${line.kind}.wav`)
              fs.writeFileSync(file, wav(result.pcm, rate))
              const totalSec = result.pcm.length / 2 / rate
              const speechSec = speechSeconds(result.pcm, rate)
              const english = line.kind === 'word' || line.kind === 'example'
              const wps = english && speechSec > 0 ? (line.text.split(/\s+/).length / speechSec).toFixed(2) : ''
              rows.push([model, char, styleName, word.word, line.kind, line.text, totalSec.toFixed(2), speechSec.toFixed(2), wps,
                result.latencyMs, result.outTokens, path.relative(args.out, file)])
              writeSummary()
              console.log(`${label}: ${totalSec.toFixed(2)}s（発話 ${speechSec.toFixed(2)}s）${result.latencyMs}ms`)
              pieces.push(result.pcm, silence(LINE_GAP_SEC, rate))
            } catch (error) {
              failures++
              console.error(`${label}: 失敗 ${error.message}`)
            }
          }
          if (pieces.length > 0) fs.writeFileSync(path.join(dir, `${word.id}-all.wav`), wav(Buffer.concat(pieces), rate))
        }
      }
    }
  }
  writeSummary()
  console.log(`\n出力: ${args.out}（summary.tsv・各条件の <id>-all.wav が 1 語ぶんの通し）`)
  if (failures > 0) {
    console.error(`失敗 ${failures} 件`)
    process.exitCode = 1
  }
}

main().catch((error) => {
  console.error(error.message)
  process.exitCode = 1
})
