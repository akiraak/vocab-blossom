import { type NavKey, type SafeHtml, html, layout, time } from '../http/html.ts'
import { type CustomWord, type Group, PARTS_OF_SPEECH, type PartOfSpeech } from '../sync/types.ts'
import type { BundledWord } from '../words/bundled.ts'
import type { GroupEntry, SenseDraft, WordDraft } from './service.ts'

// 管理画面の HTML。値はすべて html`` でエスケープされる。

/** iOS の PartOfSpeech.label と同じ */
export const POS_LABELS: Record<PartOfSpeech, string> = {
  noun: '名詞',
  verb: '動詞',
  adjective: '形容詞',
  adverb: '副詞',
  preposition: '前置詞',
  conjunction: '接続詞',
  interjection: '間投詞',
  number: '数詞',
  determiner: '限定詞',
  pronoun: '代名詞',
  modal: '助動詞',
  phrase: '熟語',
}

export const EMPTY_DRAFT: WordDraft = {
  word: '',
  meaning: '',
  pos: 'noun',
  example: '',
  exampleJa: '',
  extraSenses: [],
}

const groupPath = (id: string) => `/admin/groups/${encodeURIComponent(id)}`
const customWordPath = (id: string) => `/admin/custom-words/${encodeURIComponent(id)}`

function page(title: string, nav: NavKey, body: SafeHtml): SafeHtml {
  return layout({ title, nav, body })
}

function errorLine(error: string | undefined): SafeHtml {
  return error ? html`<p class="error" role="alert">${error}</p>` : html``
}

function posLabel(pos: string): string {
  return POS_LABELS[pos as PartOfSpeech] ?? pos
}

/** 意味を持つ語（同梱語・自作語）。extraSenses は自作語の 2 つ目以降の意味 */
type HasSenses = { meaning: string; pos: string; extraSenses?: readonly { meaning: string; pos: string }[] }

/** 一覧の「意味」の列。意味が 1 つならそのまま、複数なら「動詞: 通勤する／名詞: 通勤」（iOS の meaningSummary と同じ） */
export function meaningSummary(word: HasSenses): string {
  const extras = word.extraSenses ?? []
  if (extras.length === 0) return word.meaning
  return [word, ...extras].map((s) => `${posLabel(s.pos)}: ${s.meaning}`).join('／')
}

/** 一覧の「品詞」の列。意味が複数なら「動詞・名詞」（同じ品詞は 1 回） */
export function posSummary(word: HasSenses): string {
  const labels = [word, ...(word.extraSenses ?? [])].map((s) => posLabel(s.pos))
  return [...new Set(labels)].join('・')
}

/** 意味を足すときの品詞。まだ使っていない品詞（名詞 → 動詞 → 形容詞 → 副詞）。iOS の nextSensePos と同じ */
export function nextSensePos(draft: WordDraft): string {
  const used = new Set([draft.pos, ...draft.extraSenses.map((s) => s.pos)])
  return (['noun', 'verb', 'adjective', 'adverb'] as const).find((pos) => !used.has(pos)) ?? 'noun'
}

// --- 自作語のフォーム ---

export type DuplicateHint = {
  bundled: BundledWord
  /** グループの画面なら、その同梱語を追加するフォームの送り先 */
  addAction?: string
}

type WordFormOptions = {
  action: string
  draft: WordDraft
  submitLabel: string
  error?: string
  duplicate?: DuplicateHint
  /** 送信後に戻る先（編集画面） */
  back?: string
  /** AI チェックを出す（新しく作るフォームで、サーバーに ANTHROPIC_API_KEY があるとき） */
  assist?: AssistOptions
  /** 同じ綴りの自作語。あれば、作るとその内容を置き換えると伝える */
  replaces?: CustomWord
  /** 出し直すときに残す検索語（グループ詳細） */
  query?: string
}

export type AssistOptions = {
  /** グループの画面なら、AI が見つけた同梱語を追加するフォームの送り先 */
  addAction?: string
  /** 表示と同時に「AI で調べる」を走らせる（グループ詳細で、検索結果が 0 件のとき） */
  autorun?: boolean
}

/** AI チェックの欄。動きは http/html.ts の SCRIPT（/admin/word-assist を呼んで候補を並べる） */
function assistBox({ addAction, autorun }: AssistOptions): SafeHtml {
  return html`<div class="assist" data-assist data-add-action="${addAction ?? ''}"${autorun ? html` data-assist-autorun` : ''}
  data-pos-labels="${JSON.stringify(POS_LABELS)}">
  <div class="inline-row">
    <button type="button" data-assist-run>AI で調べる</button>
    <span class="muted" data-assist-status>英語（または意味）を入れて押すと、打ち間違い・変化した形を確かめ、意味と例文を下書きします。</span>
  </div>
  <div data-assist-results></div>
</div>`
}

/** 品詞の選択肢 */
function posOptions(selected: string): SafeHtml {
  return html`${PARTS_OF_SPEECH.map(
    (pos) => html`<option value="${pos}"${pos === selected ? html` selected` : ''}>${POS_LABELS[pos]}</option>`,
  )}`
}

/**
 * 2 つ目以降の意味 1 つ分。index は送信される並びの何番目か（「この意味を消す」が使う）。
 * index が無いのは、意味を足すための空の欄（消すチェックは出さない）
 */
function extraSenseFields(sense: SenseDraft, legend: string, index?: number): SafeHtml {
  return html`<fieldset class="sense" data-extra-sense>
    <legend>${legend}</legend>
    <label>意味<input type="text" name="extraMeaning" value="${sense.meaning}" maxlength="500"
      autocomplete="off" placeholder="例: 通勤"></label>
    <label>品詞<select name="extraPos">${posOptions(sense.pos)}</select></label>
    <label>例文（英語・任意）<textarea name="extraExample" maxlength="1000">${sense.example}</textarea></label>
    <label>例文の訳（任意）<textarea name="extraExampleJa" maxlength="1000">${sense.exampleJa}</textarea></label>
    ${
      index === undefined
        ? ''
        : html`<label class="check"><input type="checkbox" name="extraRemove" value="${String(index)}"> この意味を消す</label>`
    }
  </fieldset>`
}

const BLANK_SENSE_LEGEND = '意味を追加（品詞の違う意味・任意）'

function wordForm({
  action,
  draft,
  submitLabel,
  error,
  duplicate,
  back,
  assist,
  replaces,
  query,
}: WordFormOptions): SafeHtml {
  const blank: SenseDraft = { meaning: '', pos: nextSensePos(draft), example: '', exampleJa: '' }
  const duplicateNotice = duplicate
    ? html`<div class="notice">
        <p>「${duplicate.bundled.word}」（${duplicate.bundled.meaning}）は単語帳にあります。
          単語帳の語を使うと例文や出題の質がそろいます。</p>
        ${
          duplicate.addAction
            ? html`<form method="post" action="${duplicate.addAction}">
                <input type="hidden" name="wordId" value="${duplicate.bundled.id}">
                <button type="submit" class="primary">単語帳の「${duplicate.bundled.word}」を追加する</button>
              </form>`
            : ''
        }
      </div>`
    : ''
  const replaceNotice = replaces
    ? html`<p class="notice">「${replaces.word}」（${meaningSummary(replaces)}）はマイ単語にあります。
        作ると、新しく増やさずにそのマイ単語の内容を置き換えます（アプリの学習の記録は残ります）。</p>`
    : ''
  return html`${errorLine(error)}${duplicateNotice}${replaceNotice}
<div class="word-form">
${assist ? assistBox(assist) : ''}
<form method="post" action="${action}" class="stack" data-word-form>
  ${back ? html`<input type="hidden" name="back" value="${back}">` : ''}
  ${query ? html`<input type="hidden" name="q" value="${query}">` : ''}
  ${duplicate ? html`<input type="hidden" name="allowDuplicate" value="1">` : ''}
  <label>英語（必須）<input type="text" name="word" value="${draft.word}" required maxlength="200"
    autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="例: take care of"></label>
  <fieldset class="sense" data-primary-sense>
    <legend>${draft.extraSenses.length > 0 ? '意味 1' : '意味'}</legend>
    <label>意味（必須）<input type="text" name="meaning" value="${draft.meaning}" required maxlength="500"
      autocomplete="off" placeholder="例: 〜の世話をする"></label>
    <label>品詞<select name="pos">${posOptions(draft.pos)}</select></label>
    <label>例文（英語・任意）<textarea name="example" maxlength="1000">${draft.example}</textarea></label>
    <label>例文の訳（任意）<textarea name="exampleJa" maxlength="1000">${draft.exampleJa}</textarea></label>
  </fieldset>
  <div class="senses" data-extra-senses>
    ${draft.extraSenses.map((sense, i) => extraSenseFields(sense, `意味 ${i + 2}`, i))}
    ${extraSenseFields(blank, BLANK_SENSE_LEGEND)}
  </div>
  <template data-sense-template>${extraSenseFields(
    { meaning: '', pos: 'noun', example: '', exampleJa: '' },
    BLANK_SENSE_LEGEND,
  )}</template>
  <p class="muted">品詞の違う意味（commute の「動詞: 通勤する」「名詞: 通勤」など）は、1 つの単語にまとめられます。
    もっと足すときは、保存すると次の空の欄が出ます。例文に英語（活用形を含む）が入っていると、穴埋め問題でも出題されます。</p>
  <div><button type="submit" class="primary">${duplicate ? 'それでも自作語として作る' : submitLabel}</button></div>
</form>
</div>`
}

// --- グループ一覧 ---

export function groupsPage({ groups, error }: { groups: Group[]; error?: string }): SafeHtml {
  const rows = groups.map(
    (g) => html`<tr>
      <td><a href="${groupPath(g.id)}">${g.name}</a></td>
      <td class="num">${g.wordIds.length}</td>
      <td>${time(g.updatedAt)}</td>
      <td class="actions">
        <form method="post" action="${groupPath(g.id)}/delete"
          data-confirm="グループ「${g.name}」を削除しますか？（中の単語・マイ単語は残ります）">
          <button type="submit" class="small danger">削除</button>
        </form>
      </td>
    </tr>`,
  )
  return page(
    'グループ',
    'groups',
    html`<h1>グループ</h1>
${errorLine(error)}
<form method="post" action="/admin/groups" class="inline">
  <input type="text" name="name" placeholder="新しいグループの名前" maxlength="200" required>
  <button type="submit" class="primary">追加</button>
</form>
${
  groups.length === 0
    ? html`<p class="muted">グループはまだありません。</p>`
    : html`<table>
        <thead><tr><th>名前</th><th class="num">語数</th><th>更新</th><th></th></tr></thead>
        <tbody>${rows}</tbody>
      </table>`
}`,
  )
}

// --- グループ詳細 ---

export type SearchResult = {
  kind: 'bundled' | 'custom'
  id: string
  word: string
  meaning: string
  pos: string
  example?: string
  /** 自作語の 2 つ目以降の意味 */
  extraSenses?: readonly { meaning: string; pos: string; example?: string }[]
  level?: string
  inGroup: boolean
}

export type GroupDetailOptions = {
  group: Group
  entries: GroupEntry[]
  query: string
  results: SearchResult[]
  draft?: WordDraft
  wordError?: string
  duplicate?: DuplicateHint
  renameError?: string
  addError?: string
  aiEnabled?: boolean
  /** 作成欄の下書きと同じ綴りの自作語（作ると置き換える） */
  replaces?: CustomWord
}

/** 単語帳で見つからなかった検索語をフォームに入れる（英語なら英語欄、日本語などなら意味欄） */
export function draftFromQuery(query: string): WordDraft {
  const text = query.trim()
  if (text === '') return EMPTY_DRAFT
  if ([...text].every((ch) => ch.charCodeAt(0) < 0x80)) return { ...EMPTY_DRAFT, word: text, pos: text.includes(' ') ? 'phrase' : 'noun' }
  return { ...EMPTY_DRAFT, meaning: text }
}

function entryRow(group: Group, entry: GroupEntry, index: number, count: number): SafeHtml {
  const base = `${groupPath(group.id)}/words/${encodeURIComponent(entry.id)}`
  const move = (direction: 'up' | 'down', label: string, disabled: boolean) =>
    html`<form method="post" action="${base}/move">
      <input type="hidden" name="direction" value="${direction}">
      <button type="submit" class="small" title="${direction === 'up' ? '上へ' : '下へ'}"${disabled ? html` disabled` : ''}>${label}</button>
    </form>`
  const actions = html`${move('up', '↑', index === 0)}${move('down', '↓', index === count - 1)}
    ${
      entry.kind === 'custom'
        ? html`<a href="${customWordPath(entry.id)}?back=${encodeURIComponent(groupPath(group.id))}">編集</a>`
        : ''
    }
    <form method="post" action="${base}/remove"><button type="submit" class="small">外す</button></form>`

  if (entry.kind === 'unknown') {
    return html`<tr>
      <td class="num">${index + 1}</td>
      <td colspan="3"><span class="muted">不明な語（${entry.id}）</span></td>
      <td class="actions">${actions}</td>
    </tr>`
  }
  const tag =
    entry.kind === 'custom'
      ? html`<span class="tag custom">マイ単語</span>`
      : html`<span class="tag">${entry.level}</span>`
  return html`<tr>
    <td class="num">${index + 1}</td>
    <td>${entry.word}${tag}</td>
    <td>${meaningSummary(entry)}</td>
    <td>${posSummary(entry)}</td>
    <td class="actions">${actions}</td>
  </tr>`
}

export function groupDetailPage(options: GroupDetailOptions): SafeHtml {
  const { group, entries, query, results } = options
  const path = groupPath(group.id)
  const hasQuery = query.trim() !== ''
  // 作成欄は検索語があるときだけ（入力の誤りで出し直すときは下書きがあるので出す）
  const showsCreate = hasQuery || options.draft !== undefined

  const resultRows = results.map(
    (r) => html`<tr>
      <td>${
        r.inGroup
          ? html`${r.word}`
          : html`<label class="pick"><input type="checkbox" name="wordId" value="${r.id}"> ${r.word}</label>`
      }${r.kind === 'custom' ? html`<span class="tag custom">マイ単語</span>` : html`<span class="tag">${r.level}</span>`}</td>
      <td>${meaningSummary(r)}</td>
      <td>${posSummary(r)}</td>
      <td class="actions">${r.inGroup ? html`<span class="muted">追加済み</span>` : ''}</td>
    </tr>`,
  )
  const selectable = results.some((r) => !r.inGroup)

  const resultsBlock = !hasQuery
    ? html`<p class="muted">単語帳にない単語は、検索欄に入れると${options.aiEnabled ? ' AI で調べて' : ''}追加できます。</p>`
    : results.length === 0
      ? html`<p class="muted">「${query}」は単語帳にありません。${
          options.aiEnabled
            ? '下で AI が打ち間違いや変化した形を確かめ、単語帳に無い語は意味と例文を下書きします。'
            : '下でマイ単語として作れます。'
        }</p>`
      : html`<form method="post" action="${path}/words" data-pick-form>
          <input type="hidden" name="q" value="${query}">
          <table>
            <thead><tr><th>英語</th><th>意味</th><th>品詞</th><th></th></tr></thead>
            <tbody>${resultRows}</tbody>
          </table>
          ${
            selectable
              ? html`<p><button type="submit" class="primary" data-pick-submit>選んだ単語を追加</button></p>`
              : ''
          }
        </form>`

  const createTitle = hasQuery ? `「${query.trim()}」をマイ単語として作る` : 'マイ単語として作る'
  const createBlock = showsCreate
    ? html`<h3 id="new-word">${createTitle}</h3>
${results.length > 0 ? html`<p class="muted">探している語が上の一覧に無いときに使います。</p>` : ''}
${wordForm({
  action: `${path}/custom-words`,
  draft: options.draft ?? draftFromQuery(query),
  submitLabel: '作って追加',
  error: options.wordError,
  duplicate: options.duplicate,
  replaces: options.replaces,
  query,
  assist: options.aiEnabled
    ? { addAction: `${path}/words`, autorun: results.length === 0 && options.draft === undefined }
    : undefined,
})}`
    : ''

  return page(
    group.name,
    'groups',
    html`<p class="breadcrumb"><a href="/admin/groups">← グループ一覧</a></p>
<h1>${group.name}</h1>
<p class="muted">${group.wordIds.length} 語・更新 ${time(group.updatedAt)}</p>

<h2 id="words">単語・フレーズ</h2>
${
  entries.length === 0
    ? html`<p class="muted">まだ単語がありません。下の「単語を追加」で検索して入れてください（単語帳にない単語も作れます）。</p>`
    : html`<table>
        <thead><tr><th class="num">#</th><th>英語</th><th>意味</th><th>品詞</th><th></th></tr></thead>
        <tbody>${entries.map((e, i) => entryRow(group, e, i, entries.length))}</tbody>
      </table>`
}

<h2 id="add">単語を追加</h2>
<form method="get" action="${path}#add" class="inline">
  <input type="search" name="q" value="${query}" placeholder="英語か意味で検索（単語帳にない語も追加できます）" autocomplete="off">
  <button type="submit">検索</button>
</form>
${errorLine(options.addError)}
${resultsBlock}
${createBlock}

<h2 id="rename">名前の変更</h2>
${errorLine(options.renameError)}
<form method="post" action="${path}/rename" class="inline">
  <input type="text" name="name" value="${group.name}" maxlength="200" required>
  <button type="submit">変更</button>
</form>

<div class="danger-zone">
  <form method="post" action="${path}/delete"
    data-confirm="グループ「${group.name}」を削除しますか？（中の単語・マイ単語は残ります）">
    <button type="submit" class="danger">このグループを削除</button>
  </form>
</div>`,
  )
}

// --- マイ単語 ---

function groupLinks(groups: Group[]): SafeHtml {
  if (groups.length === 0) return html`<span class="muted">なし</span>`
  return html`${groups.map((g, i) => html`${i > 0 ? '、' : ''}<a href="${groupPath(g.id)}">${g.name}</a>`)}`
}

export type CustomWordsOptions = {
  words: CustomWord[]
  groupsByWord: Map<string, Group[]>
  draft?: WordDraft
  error?: string
  duplicate?: DuplicateHint
  aiEnabled?: boolean
  /** 下書きと同じ綴りの自作語（作ると置き換える） */
  replaces?: CustomWord
}

export function customWordsPage({
  words,
  groupsByWord,
  draft,
  error,
  duplicate,
  aiEnabled,
  replaces,
}: CustomWordsOptions): SafeHtml {
  const rows = words.map(
    (w) => html`<tr>
      <td><a href="${customWordPath(w.wordId)}">${w.word}</a></td>
      <td>${meaningSummary(w)}</td>
      <td>${posSummary(w)}</td>
      <td>${groupLinks(groupsByWord.get(w.wordId) ?? [])}</td>
      <td>${time(w.updatedAt)}</td>
      <td class="actions">
        <form method="post" action="${customWordPath(w.wordId)}/delete"
          data-confirm="「${w.word}」を削除しますか？（すべてのグループから外れ、アプリでは学習の記録も消えます）">
          <button type="submit" class="small danger">削除</button>
        </form>
      </td>
    </tr>`,
  )
  return page(
    'マイ単語',
    'custom-words',
    html`<h1>マイ単語</h1>
<p class="muted">単語帳に無い、自分で登録した単語・フレーズ。グループに入っていないものも含めてすべて出します。</p>
${
  words.length === 0
    ? html`<p class="muted">マイ単語はまだありません。</p>`
    : html`<table>
        <thead><tr><th>英語</th><th>意味</th><th>品詞</th><th>グループ</th><th>更新</th><th></th></tr></thead>
        <tbody>${rows}</tbody>
      </table>`
}

<h2 id="new-word">マイ単語を作る</h2>
${wordForm({
  action: '/admin/custom-words',
  draft: draft ?? EMPTY_DRAFT,
  submitLabel: '作る',
  error,
  duplicate,
  replaces,
  assist: aiEnabled ? {} : undefined,
})}`,
  )
}

export type CustomWordEditOptions = {
  word: CustomWord
  groups: Group[]
  back: string
  draft?: WordDraft
  error?: string
}

export function customWordEditPage({ word, groups, back, draft, error }: CustomWordEditOptions): SafeHtml {
  const path = customWordPath(word.wordId)
  return page(
    word.word,
    'custom-words',
    html`<p class="breadcrumb"><a href="${back}">← 戻る</a></p>
<h1>${word.word}<span class="tag custom">マイ単語</span></h1>
<p class="muted">作成 ${time(word.createdAt)}・更新 ${time(word.updatedAt)}</p>
<p>入っているグループ: ${groupLinks(groups)}</p>

<h2>編集</h2>
${wordForm({ action: path, draft: draft ?? word, submitLabel: '保存', error, back })}

<div class="danger-zone">
  <form method="post" action="${path}/delete"
    data-confirm="「${word.word}」を削除しますか？（すべてのグループから外れ、アプリでは学習の記録も消えます）">
    <input type="hidden" name="back" value="${back}">
    <button type="submit" class="danger">この単語を削除</button>
  </form>
</div>`,
  )
}

export function notFoundPage(message: string): SafeHtml {
  return page(
    '見つかりません',
    'groups',
    html`<h1>見つかりません</h1><p>${message}</p><p><a href="/admin/groups">グループ一覧へ</a></p>`,
  )
}
