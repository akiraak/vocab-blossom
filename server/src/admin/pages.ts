import { type NavKey, type SafeHtml, html, layout, time } from '../http/html.ts'
import { type CustomWord, type Group, PARTS_OF_SPEECH, type PartOfSpeech } from '../sync/types.ts'
import type { BundledWord } from '../words/bundled.ts'
import type { GroupEntry, WordDraft } from './service.ts'

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

export const EMPTY_DRAFT: WordDraft = { word: '', meaning: '', pos: 'noun', example: '', exampleJa: '' }

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
}

function wordForm({ action, draft, submitLabel, error, duplicate, back }: WordFormOptions): SafeHtml {
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
  return html`${errorLine(error)}${duplicateNotice}
<form method="post" action="${action}" class="stack">
  ${back ? html`<input type="hidden" name="back" value="${back}">` : ''}
  ${duplicate ? html`<input type="hidden" name="allowDuplicate" value="1">` : ''}
  <label>英語（必須）<input type="text" name="word" value="${draft.word}" required maxlength="200"
    autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="例: take care of"></label>
  <label>意味（必須）<input type="text" name="meaning" value="${draft.meaning}" required maxlength="500"
    autocomplete="off" placeholder="例: 〜の世話をする"></label>
  <label>品詞<select name="pos">${PARTS_OF_SPEECH.map(
    (pos) => html`<option value="${pos}"${pos === draft.pos ? html` selected` : ''}>${POS_LABELS[pos]}</option>`,
  )}</select></label>
  <label>例文（英語・任意）<textarea name="example" maxlength="1000">${draft.example}</textarea></label>
  <label>例文の訳（任意）<textarea name="exampleJa" maxlength="1000">${draft.exampleJa}</textarea></label>
  <p class="muted">例文に英語（活用形を含む）が入っていると、穴埋め問題でも出題されます。</p>
  <div><button type="submit" class="primary">${duplicate ? 'それでも自作語として作る' : submitLabel}</button></div>
</form>`
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
    <td>${entry.meaning}</td>
    <td>${posLabel(entry.pos)}</td>
    <td class="actions">${actions}</td>
  </tr>`
}

export function groupDetailPage(options: GroupDetailOptions): SafeHtml {
  const { group, entries, query, results } = options
  const path = groupPath(group.id)

  const resultRows = results.map(
    (r) => html`<tr>
      <td>${r.word}${r.kind === 'custom' ? html`<span class="tag custom">マイ単語</span>` : html`<span class="tag">${r.level}</span>`}</td>
      <td>${r.meaning}</td>
      <td>${posLabel(r.pos)}</td>
      <td class="actions">${
        r.inGroup
          ? html`<span class="muted">追加済み</span>`
          : html`<form method="post" action="${path}/words">
              <input type="hidden" name="wordId" value="${r.id}">
              <input type="hidden" name="q" value="${query}">
              <button type="submit" class="small primary">追加</button>
            </form>`
      }</td>
    </tr>`,
  )

  return page(
    group.name,
    'groups',
    html`<p class="breadcrumb"><a href="/admin/groups">← グループ一覧</a></p>
<h1>${group.name}</h1>
<p class="muted">${group.wordIds.length} 語・更新 ${time(group.updatedAt)}</p>

<h2 id="words">単語・フレーズ</h2>
${
  entries.length === 0
    ? html`<p class="muted">まだ単語がありません。下の「単語帳から追加」か「マイ単語を作って追加」で入れてください。</p>`
    : html`<table>
        <thead><tr><th class="num">#</th><th>英語</th><th>意味</th><th>品詞</th><th></th></tr></thead>
        <tbody>${entries.map((e, i) => entryRow(group, e, i, entries.length))}</tbody>
      </table>`
}

<h2 id="search">単語帳から追加</h2>
<form method="get" action="${path}#search" class="inline">
  <input type="search" name="q" value="${query}" placeholder="英語か意味で検索" autocomplete="off">
  <button type="submit">検索</button>
</form>
${errorLine(options.addError)}
${
  query.trim() === ''
    ? ''
    : results.length === 0
      ? html`<p class="muted">「${query}」は見つかりませんでした。下のフォームでマイ単語として作れます。</p>`
      : html`<table>
          <thead><tr><th>英語</th><th>意味</th><th>品詞</th><th></th></tr></thead>
          <tbody>${resultRows}</tbody>
        </table>`
}

<h2 id="new-word">マイ単語を作って追加</h2>
${wordForm({
  action: `${path}/custom-words`,
  draft: options.draft ?? EMPTY_DRAFT,
  submitLabel: '作って追加',
  error: options.wordError,
  duplicate: options.duplicate,
})}

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
}

export function customWordsPage({ words, groupsByWord, draft, error, duplicate }: CustomWordsOptions): SafeHtml {
  const rows = words.map(
    (w) => html`<tr>
      <td><a href="${customWordPath(w.wordId)}">${w.word}</a></td>
      <td>${w.meaning}</td>
      <td>${posLabel(w.pos)}</td>
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
${wordForm({ action: '/admin/custom-words', draft: draft ?? EMPTY_DRAFT, submitLabel: '作る', error, duplicate })}`,
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
