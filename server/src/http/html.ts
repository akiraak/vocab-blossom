// HTML のタグ付きテンプレート。埋め込む値は必ずエスケープする（XSS 対策）。
// エスケープしたくない HTML は SafeHtml（html`...` の戻り値か raw()）として渡す。

export class SafeHtml {
  readonly value: string

  constructor(value: string) {
    this.value = value
  }

  toString(): string {
    return this.value
  }
}

const ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (ch) => ESCAPES[ch])
}

/** 信頼できる HTML 文字列をそのまま埋め込む。利用者の入力には使わない */
export function raw(value: string): SafeHtml {
  return new SafeHtml(value)
}

function render(value: unknown): string {
  if (value instanceof SafeHtml) return value.value
  if (value === null || value === undefined || value === false) return ''
  if (Array.isArray(value)) return value.map(render).join('')
  return escapeHtml(String(value))
}

export function html(strings: TemplateStringsArray, ...values: unknown[]): SafeHtml {
  let out = strings[0]
  values.forEach((value, i) => {
    out += render(value) + strings[i + 1]
  })
  return new SafeHtml(out)
}

export type LayoutOptions = {
  title: string
  body: SafeHtml
}

const STYLE = `
  :root { color-scheme: light dark; --accent: #d9468b; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif;
         margin: 0; line-height: 1.6; }
  header { padding: 12px 16px; border-bottom: 1px solid #8884; display: flex; gap: 16px; align-items: baseline; }
  header .brand { font-weight: 700; color: var(--accent); text-decoration: none; }
  header nav a { margin-right: 12px; }
  main { max-width: 960px; margin: 0 auto; padding: 16px; }
`

/** 管理画面の共通レイアウト（ヘッダー・CSS） */
export function layout({ title, body }: LayoutOptions): SafeHtml {
  return html`<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} | vocab-blossom 管理</title>
<style>${raw(STYLE)}</style>
</head>
<body>
<header>
  <a class="brand" href="/admin">vocab-blossom</a>
</header>
<main>
${body}
</main>
</body>
</html>`
}
