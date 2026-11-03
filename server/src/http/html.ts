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

export type NavKey = 'groups' | 'custom-words'

export type LayoutOptions = {
  title: string
  body: SafeHtml
  /** ヘッダーで強調するメニュー */
  nav?: NavKey
}

const STYLE = `
  :root { color-scheme: light dark; --accent: #d9468b; --line: #8884; --muted: #888;
          --bg-soft: #8881; --danger: #c0392b; }
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif;
         margin: 0; line-height: 1.6; }
  a { color: var(--accent); }
  header { padding: 12px 16px; border-bottom: 1px solid var(--line); display: flex; gap: 20px;
           align-items: baseline; flex-wrap: wrap; }
  header .brand { font-weight: 700; color: var(--accent); text-decoration: none; }
  header nav { display: flex; gap: 16px; }
  header nav a { color: inherit; text-decoration: none; padding-bottom: 2px; }
  header nav a[aria-current="page"] { border-bottom: 2px solid var(--accent); font-weight: 600; }
  main { max-width: 960px; margin: 0 auto; padding: 16px; }
  h1 { font-size: 1.5rem; margin: 8px 0 16px; }
  h2 { font-size: 1.1rem; margin: 28px 0 8px; }
  .breadcrumb { font-size: 0.9rem; margin: 0; }
  .muted { color: var(--muted); font-size: 0.9rem; }
  .error { color: var(--danger); font-weight: 600; }
  .notice { background: var(--bg-soft); border-left: 4px solid var(--accent); padding: 8px 12px; margin: 12px 0; }
  table { border-collapse: collapse; width: 100%; }
  th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: middle; }
  th { font-size: 0.85rem; color: var(--muted); font-weight: 600; }
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
  td.actions { white-space: nowrap; text-align: right; }
  td.actions form { display: inline; }
  .tag { display: inline-block; font-size: 0.75rem; padding: 0 6px; border-radius: 4px;
         background: var(--bg-soft); border: 1px solid var(--line); margin-left: 4px; white-space: nowrap; }
  .tag.custom { border-color: var(--accent); color: var(--accent); }
  form.inline { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin: 8px 0; }
  form.stack { display: grid; gap: 8px; max-width: 560px; }
  form.stack label { display: grid; gap: 2px; font-size: 0.9rem; }
  input[type="text"], input[type="search"], select, textarea {
    font: inherit; padding: 6px 8px; border: 1px solid var(--line); border-radius: 6px;
    background: transparent; color: inherit; }
  input[type="text"], input[type="search"] { min-width: 240px; }
  textarea { min-height: 3em; }
  button { font: inherit; padding: 4px 12px; border-radius: 6px; border: 1px solid var(--line);
           background: var(--bg-soft); color: inherit; cursor: pointer; }
  button.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  button.danger { color: var(--danger); }
  button.small { padding: 0 8px; font-size: 0.85rem; }
  button:disabled { opacity: 0.4; cursor: default; }
  .danger-zone { margin-top: 40px; padding-top: 12px; border-top: 1px solid var(--line); }
  .assist { max-width: 560px; margin: 8px 0 12px; }
  .assist .inline-row { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
  .assist .candidate { background: var(--bg-soft); border-left: 4px solid var(--accent); padding: 6px 12px; margin: 8px 0; }
  .assist .candidate p { margin: 2px 0; }
  .assist .candidate form { margin: 4px 0 0; }
`

// 画面の動きはこれだけ: 削除の確認、日時を端末の時刻で表示する、自作語のフォームの AI チェック
const SCRIPT = `
  document.addEventListener('submit', (event) => {
    const message = event.target.getAttribute('data-confirm')
    if (message && !window.confirm(message)) event.preventDefault()
  })
  for (const el of document.querySelectorAll('time[datetime]')) {
    const d = new Date(el.getAttribute('datetime'))
    if (!Number.isNaN(d.getTime())) {
      el.textContent = d.toLocaleString('ja-JP', { dateStyle: 'short', timeStyle: 'short' })
    }
  }

  // AI チェック: /admin/word-assist の候補を並べる。値は textContent で入れる（HTML として解釈しない）
  const ASSIST_REASONS = {
    typo: '綴りの誤りかもしれません',
    inflection: '変化した形のもとの形です',
    variant: '綴り・言い方の違いです',
    translation: '日本語から探しました',
  }
  const ASSIST_ERRORS = {
    'ai-unavailable': 'サーバーで AI が使えません（ANTHROPIC_API_KEY が未設定）',
    'rate-limited': 'AI を短い間に使いすぎました。少し待ってからもう一度試してください',
    'ai-failed': 'AI が答えられませんでした。もう一度試すか、そのまま入力してください',
  }
  function el(tag, className, text) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text !== undefined) node.textContent = text
    return node
  }
  for (const box of document.querySelectorAll('[data-assist]')) {
    const form = box.parentElement.querySelector('form[data-word-form]')
    const field = (name) => form.elements.namedItem(name)
    const button = box.querySelector('[data-assist-run]')
    const status = box.querySelector('[data-assist-status]')
    const results = box.querySelector('[data-assist-results]')
    const addAction = box.getAttribute('data-add-action')
    const posLabels = JSON.parse(box.getAttribute('data-pos-labels'))

    const candidateView = (c) => {
      const item = el('div', 'candidate')
      const head = el('p')
      head.append(el('strong', '', c.word), ' ', el('span', 'muted', posLabels[c.pos] || c.pos))
      if (c.bundled) head.append(el('span', 'tag custom', '単語帳にあります'))
      item.append(head, el('p', '', c.bundled ? c.bundled.meaning : c.meaning))
      if (ASSIST_REASONS[c.reason]) item.append(el('p', 'muted', ASSIST_REASONS[c.reason]))
      if (c.bundled) {
        if (addAction) {
          const add = el('form')
          add.method = 'post'
          add.action = addAction
          const id = el('input')
          id.type = 'hidden'
          id.name = 'wordId'
          id.value = c.bundled.id
          const submit = el('button', 'primary', '単語帳の「' + c.bundled.word + '」を追加する')
          submit.type = 'submit'
          add.append(id, submit)
          item.append(add)
        } else {
          item.append(el('p', 'muted', '単語帳にあるので、作らなくてもアプリで学習できます'))
        }
      } else {
        if (c.example) item.append(el('p', 'muted', c.example))
        const fill = el('button', '', 'この内容を入れる')
        fill.type = 'button'
        fill.addEventListener('click', () => {
          for (const name of ['word', 'meaning', 'pos', 'example', 'exampleJa']) field(name).value = c[name]
        })
        item.append(fill)
      }
      return item
    }

    button.addEventListener('click', async () => {
      const text = field('word').value.trim() || field('meaning').value.trim()
      if (!text) {
        status.textContent = '英語か意味を入れてください'
        return
      }
      button.disabled = true
      status.textContent = 'AI で調べています…'
      results.replaceChildren()
      try {
        const res = await fetch('/admin/word-assist', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ text }),
        })
        const body = await res.json().catch(() => ({}))
        if (!res.ok) {
          status.textContent = ASSIST_ERRORS[body.error] || 'エラーが起きました（' + res.status + '）'
          return
        }
        status.textContent = '「' + body.text + '」の候補:'
        results.append(...body.candidates.map(candidateView))
      } catch {
        status.textContent = 'サーバーにつながりませんでした'
      } finally {
        button.disabled = false
      }
    })
  }
`

/** 日時（ミリ秒）。JS が無ければ UTC のまま出す */
export function time(ms: number): SafeHtml {
  const iso = new Date(ms).toISOString()
  return html`<time datetime="${iso}">${iso.slice(0, 16).replace('T', ' ')} UTC</time>`
}

const NAV: { key: NavKey; href: string; label: string }[] = [
  { key: 'groups', href: '/admin/groups', label: 'グループ' },
  { key: 'custom-words', href: '/admin/custom-words', label: 'マイ単語' },
]

/** 管理画面の共通レイアウト（ヘッダー・CSS・JS） */
export function layout({ title, body, nav }: LayoutOptions): SafeHtml {
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
  <nav>${NAV.map(
    (item) =>
      html`<a href="${item.href}"${item.key === nav ? raw(' aria-current="page"') : ''}>${item.label}</a>`,
  )}</nav>
</header>
<main>
${body}
</main>
<script>${raw(SCRIPT)}</script>
</body>
</html>`
}
