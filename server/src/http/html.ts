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
  .assist .candidate label.sense-pick { display: block; margin: 2px 0; }
  .assist .candidate .example { margin-left: 1.6em; }
  label.pick { display: inline-flex; gap: 6px; align-items: center; cursor: pointer; }
  fieldset.sense { border: 1px solid var(--line); border-radius: 6px; padding: 8px 12px; margin: 0;
                   display: grid; gap: 8px; }
  fieldset.sense legend { font-size: 0.9rem; font-weight: 600; padding: 0 4px; }
  .senses { display: grid; gap: 8px; }
  form.stack label.check { display: flex; gap: 6px; align-items: center; }
  .hint { margin: 8px 0; }
  input[type="checkbox"] { width: 1.1em; height: 1.1em; accent-color: var(--accent); }
  /* グループ詳細の「単語を追加」: ページ上部の枠 */
  .add-card { border: 1px solid var(--line); border-top: 4px solid var(--accent); border-radius: 10px;
              padding: 12px 16px 16px; margin: 16px 0 28px; }
  .add-card h2 { margin: 0 0 8px; font-size: 1.25rem; }
  .add-card h3 { margin: 20px 0 4px; font-size: 1.05rem; }
  form.search-row { display: flex; gap: 8px; margin: 0 0 8px; }
  form.search-row input[type="search"] { flex: 1; min-width: 0; font-size: 1.1rem; padding: 8px 12px; }
  form.search-row button { padding: 8px 20px; }
  .pick-bar { position: sticky; top: 0; z-index: 1; background: Canvas; display: flex; gap: 12px;
              justify-content: space-between; align-items: center; flex-wrap: wrap; padding: 8px 0; }
  tr[data-pick-row] { cursor: pointer; }
  tr[data-pick-row]:hover { background: var(--bg-soft); }
  tr:has(input[name="wordId"]:checked) { background: color-mix(in srgb, var(--accent) 14%, transparent); }
  table.results .example { font-size: 0.85rem; }
  details.more { margin: 8px 0; }
  details > summary { cursor: pointer; }
  details.more > summary { color: var(--muted); padding: 6px 0; }
  details.create { margin: 16px 0 0; }
  details.create > summary { color: var(--accent); font-weight: 600; padding: 6px 0; }
  details.create[open] > summary { margin-bottom: 8px; }
  .assist .candidate .actions-row { display: flex; gap: 8px; flex-wrap: wrap; margin: 6px 0 2px; }
`

// 画面の動きはこれだけ: 削除の確認、日時を端末の時刻で表示する、検索結果でチェックした数の表示、
// 自作語のフォームの意味の欄を足す、AI チェック（0 件なら自動で調べる・品詞違いの候補を 1 枚にまとめる・その内容で作る）
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
  // グループ詳細の検索結果: 「選んだ単語を追加（N）」に数を出し、1 つも選んでいなければ押せないようにする。
  // 行のどこを押してもチェックが切り替わる
  for (const pick of document.querySelectorAll('form[data-pick-form]')) {
    const submit = pick.querySelector('[data-pick-submit]')
    if (!submit) continue
    const update = () => {
      const n = pick.querySelectorAll('input[name="wordId"]:checked').length
      submit.textContent = n === 0 ? '選んだ単語を追加' : '選んだ ' + n + ' 語を追加'
      submit.disabled = n === 0
    }
    pick.addEventListener('change', update)
    pick.addEventListener('click', (event) => {
      const row = event.target.closest('tr[data-pick-row]')
      if (!row || event.target.closest('label, input, a, button')) return
      const check = row.querySelector('input[name="wordId"]')
      check.checked = !check.checked
      update()
    })
    update()
  }

  const spellingOf = (word) => word.trim().toLowerCase()
  // 意味を足すための欄の品詞。まだ使っていない品詞（iOS の nextSensePos と同じ）
  const nextPos = (senses) =>
    ['noun', 'verb', 'adjective', 'adverb'].find((pos) => !senses.some((s) => s.pos === pos)) || 'noun'

  // 自作語のフォームの意味の欄: 「＋ 意味を追加」で欄を足す・AI の候補でまとめて差し替える
  function senseTools(form) {
    const field = (name) => form.elements.namedItem(name)
    const extraList = form.querySelector('[data-extra-senses]')
    const senseTemplate = form.querySelector('template[data-sense-template]')
    const primaryLegend = form.querySelector('[data-primary-sense] legend')
    const addBlock = (sense, legend) => {
      extraList.append(senseTemplate.content.cloneNode(true))
      const block = extraList.lastElementChild
      block.querySelector('legend').textContent = legend
      const set = (name, value) => { block.querySelector('[name="' + name + '"]').value = value }
      set('extraMeaning', sense.meaning)
      set('extraPos', sense.pos)
      set('extraExample', sense.example)
      set('extraExampleJa', sense.exampleJa)
      primaryLegend.textContent = '意味 1'
      return block
    }
    const currentSenses = () => {
      const senses = [{ pos: field('pos').value }]
      for (const select of extraList.querySelectorAll('[name="extraPos"]')) senses.push({ pos: select.value })
      return senses
    }
    // 空の欄を 1 つ足す
    const addBlank = () => {
      const n = extraList.querySelectorAll('[data-extra-sense]').length
      const block = addBlock({ meaning: '', pos: nextPos(currentSenses()), example: '', exampleJa: '' }, '意味 ' + (n + 2))
      block.querySelector('[name="extraMeaning"]').focus()
    }
    // 英語・1 つ目の意味・2 つ目以降の意味を差し替える
    const fill = (word, senses) => {
      const [first, ...rest] = senses
      field('word').value = word
      for (const name of ['meaning', 'pos', 'example', 'exampleJa']) field(name).value = first[name]
      for (const block of extraList.querySelectorAll('[data-extra-sense]')) block.remove()
      rest.forEach((sense, i) => addBlock(sense, '意味 ' + (i + 2)))
      primaryLegend.textContent = rest.length > 0 ? '意味 1' : '意味'
    }
    return { field, addBlank, fill }
  }
  for (const form of document.querySelectorAll('form[data-word-form]')) {
    const tools = senseTools(form)
    const add = form.querySelector('[data-add-sense]')
    if (add) add.addEventListener('click', tools.addBlank)
  }

  for (const box of document.querySelectorAll('[data-assist]')) {
    const form = box.parentElement.querySelector('form[data-word-form]')
    const { field, fill } = senseTools(form)
    const button = box.querySelector('[data-assist-run]')
    const status = box.querySelector('[data-assist-status]')
    const results = box.querySelector('[data-assist-results]')
    const addAction = box.getAttribute('data-add-action')
    const posLabels = JSON.parse(box.getAttribute('data-pos-labels'))
    // フォームがたたまれていれば開く
    const openForm = () => {
      const details = form.closest('details')
      if (details) details.open = true
    }

    // 単語帳にある語: 案内して、グループの画面ならそのまま追加できる
    const bundledView = (c) => {
      const item = el('div', 'candidate')
      const head = el('p')
      head.append(el('strong', '', c.word), ' ', el('span', 'muted', posLabels[c.pos] || c.pos))
      head.append(el('span', 'tag custom', '単語帳にあります'))
      item.append(head, el('p', '', c.bundled.meaning))
      if (ASSIST_REASONS[c.reason]) item.append(el('p', 'muted', ASSIST_REASONS[c.reason]))
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
      return item
    }

    // 単語帳に無い語: 同じ綴りの候補（commute の動詞・名詞）を 1 枚にまとめ、意味ごとに入れる・入れないを選ぶ。
    // 「この内容で作る」はフォームを埋めてそのまま送り、「直してから作る」はフォームを埋めて開く
    const newWordView = (group) => {
      const first = group[0]
      const item = el('div', 'candidate')
      const head = el('p')
      head.append(el('strong', '', first.word))
      if (group.length === 1) head.append(' ', el('span', 'muted', posLabels[first.pos] || first.pos))
      head.append(el('span', 'tag custom', '新しく作る'))
      item.append(head)
      if (ASSIST_REASONS[first.reason]) item.append(el('p', 'muted', ASSIST_REASONS[first.reason]))
      const checks = group.map((c) => {
        const line = el('label', 'sense-pick')
        const check = el('input')
        check.type = 'checkbox'
        check.checked = true
        if (group.length > 1) line.append(check, ' ', el('span', 'muted', posLabels[c.pos] || c.pos), ' ')
        line.append(c.meaning)
        item.append(line)
        if (c.example) item.append(el('p', 'muted example', c.example))
        return check
      })
      const fillChecked = () => {
        const senses = group.filter((_, i) => checks[i].checked)
        if (senses.length === 0) {
          status.textContent = '入れる意味を 1 つ以上選んでください'
          return false
        }
        fill(first.word, senses)
        return true
      }
      const row = el('div', 'actions-row')
      const create = el('button', 'primary', addAction ? 'この内容で作って追加' : 'この内容で作る')
      create.type = 'button'
      create.addEventListener('click', () => {
        if (fillChecked()) form.requestSubmit()
      })
      const edit = el('button', '', '直してから作る')
      edit.type = 'button'
      edit.addEventListener('click', () => {
        if (!fillChecked()) return
        openForm()
        status.textContent = '「' + first.word + '」をフォームに入れました。直して「' +
          form.querySelector('button[type="submit"]').textContent + '」を押してください'
        field('meaning').focus()
      })
      row.append(create, edit)
      item.append(row)
      return item
    }

    const run = async () => {
      const text = field('word').value.trim() || field('meaning').value.trim()
      if (!text) {
        status.textContent = '英語か意味を入れてください'
        openForm()
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
          openForm()
          return
        }
        if (body.candidates.length === 0) {
          status.textContent = '「' + body.text + '」の候補が見つかりませんでした。自分で入力して作ってください'
          openForm()
          return
        }
        status.textContent = '「' + body.text + '」の候補:'
        // 並びは AI が返した順。単語帳に無い語は、同じ綴りが最初に出た位置に 1 枚だけ置く
        const views = []
        const bySpelling = new Map()
        for (const c of body.candidates) {
          if (c.bundled) {
            views.push(bundledView(c))
            continue
          }
          const key = spellingOf(c.word)
          let group = bySpelling.get(key)
          if (!group) {
            group = []
            bySpelling.set(key, group)
            views.push(group)
          }
          if (!group.some((g) => g.pos === c.pos && g.meaning === c.meaning)) group.push(c)
        }
        results.append(...views.map((v) => (Array.isArray(v) ? newWordView(v) : v)))
        // 入力どおりの綴りで単語帳に無い語が返れば、最初からフォームに入れておく（iPhone で最初から選んでおくのと同じ）。
        // 自分で意味を入れていたら上書きしない
        const first = body.candidates[0]
        if (first && first.reason === 'exact' && !first.bundled && !field('meaning').value.trim()) {
          fill(first.word, bySpelling.get(spellingOf(first.word)))
        }
      } catch {
        status.textContent = 'サーバーにつながりませんでした'
        openForm()
      } finally {
        button.disabled = false
      }
    }

    button.addEventListener('click', run)
    // グループ詳細で検索結果が 0 件のときは、開いたらすぐ調べる
    if (box.hasAttribute('data-assist-autorun')) run()
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
