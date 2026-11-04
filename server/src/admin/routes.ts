import { PayloadTooLargeError, readForm } from '../http/body.ts'
import type { SafeHtml } from '../http/html.ts'
import { htmlPage, redirect, text } from '../http/responses.ts'
import type { Handler, Route, RouteContext } from '../http/router.ts'
import { isCustomWordId } from '../sync/types.ts'
import { type BundledWords, searchWords } from '../words/bundled.ts'
import {
  customWordEditPage,
  customWordsPage,
  type DuplicateHint,
  draftFromQuery,
  groupDetailPage,
  groupsPage,
  notFoundPage,
  type SearchResult,
} from './pages.ts'
import {
  AdminInputError,
  AdminNotFoundError,
  type AdminService,
  type MoveDirection,
  type WordDraft,
  isBlankSense,
  validateDraft,
} from './service.ts'

// 管理画面のルート。素の HTML フォームで、POST の後は 303 で GET に戻す（PRG）。
// 入力の誤りは同じ画面を 400 で出し直す。認証・ADMIN_ENABLED・Origin の確認は app.ts の関所で済んでいる。

export const FORM_BODY_LIMIT = 64 * 1024

const CUSTOM_WORDS_PATH = '/admin/custom-words'
const groupPath = (id: string) => `/admin/groups/${encodeURIComponent(id)}`

type FormHandler = (form: URLSearchParams, request: Request, context: RouteContext) => Response | Promise<Response>

/** 例外を 404 / 413 にする */
function guarded(handler: Handler): Handler {
  return async (request, context) => {
    try {
      return await handler(request, context)
    } catch (error) {
      if (error instanceof AdminNotFoundError) return htmlPage(notFoundPage(error.message), 404)
      if (error instanceof PayloadTooLargeError) return text('payload too large', 413)
      throw error
    }
  }
}

function withForm(handler: FormHandler): Handler {
  return guarded(async (request, context) =>
    handler(await readForm(request, FORM_BODY_LIMIT), request, context),
  )
}

function field(form: URLSearchParams, name: string): string {
  return form.get(name) ?? ''
}

/**
 * フォームの中身。2 つ目以降の意味は extraMeaning・extraPos・extraExample・extraExampleJa が同じ数だけ並ぶ。
 * extraRemove（何番目か）に入っている意味と、欄がすべて空の意味（足すための空の欄）は落とす
 */
export function draftFrom(form: URLSearchParams): WordDraft {
  const meanings = form.getAll('extraMeaning')
  const poses = form.getAll('extraPos')
  const examples = form.getAll('extraExample')
  const exampleJas = form.getAll('extraExampleJa')
  const removed = new Set(form.getAll('extraRemove'))
  const extraSenses = meanings
    .map((meaning, i) => ({
      meaning,
      pos: poses[i] ?? '',
      example: examples[i] ?? '',
      exampleJa: exampleJas[i] ?? '',
    }))
    .filter((sense, i) => !removed.has(String(i)) && !isBlankSense(sense))
  return {
    word: field(form, 'word'),
    meaning: field(form, 'meaning'),
    pos: field(form, 'pos'),
    example: field(form, 'example'),
    exampleJa: field(form, 'exampleJa'),
    extraSenses,
  }
}

/** 戻り先は管理画面の中のパスだけ（オープンリダイレクト対策） */
export function safeBack(value: string | null, fallback: string): string {
  if (!value) return fallback
  if (!value.startsWith('/admin/') && value !== '/admin') return fallback
  if (value.startsWith('//') || value.includes('\\')) return fallback
  return value
}

const badRequest = (body: SafeHtml) => htmlPage(body, 400)

export function adminRoutes({
  service,
  bundled,
  aiEnabled = false,
}: {
  service: AdminService
  bundled: BundledWords
  /** 自作語のフォームに「AI で調べる」を出す */
  aiEnabled?: boolean
}): Route[] {
  // --- 画面の組み立て ---

  /**
   * グループ詳細の検索。同梱語 + 自作語をひとつの並び（同梱語 → 自作語。iOS の allWords と同じ）で順位づけし、件数の上限は無い。
   * グループに入っている語は「追加済み」にする
   */
  function searchResults(groupId: string, query: string): SearchResult[] {
    if (query.trim() === '') return []
    const group = service.getGroup(groupId)
    const inGroup = new Set(group.wordIds)
    const words: SearchResult[] = [
      ...bundled.all.map((w): SearchResult => ({
        kind: 'bundled',
        id: w.id,
        word: w.word,
        meaning: w.meaning,
        pos: w.pos,
        example: w.example,
        level: w.level,
        inGroup: inGroup.has(w.id),
      })),
      ...service.listCustomWords().map((w): SearchResult => ({
        kind: 'custom',
        id: w.wordId,
        word: w.word,
        meaning: w.meaning,
        pos: w.pos,
        example: w.example,
        extraSenses: w.extraSenses,
        inGroup: inGroup.has(w.wordId),
      })),
    ]
    return searchWords(words, query, Number.POSITIVE_INFINITY)
  }

  function renderGroup(
    groupId: string,
    query: string,
    extra: Partial<Parameters<typeof groupDetailPage>[0]> = {},
  ): SafeHtml {
    const group = service.getGroup(groupId)
    // 作成欄の下書き（入力の誤りで出し直すときは送られた下書き、そうでなければ検索語から）の綴りの自作語があれば、置き換えになると伝える
    const word = extra.draft?.word ?? (query.trim() === '' ? '' : draftFromQuery(query).word)
    return groupDetailPage({
      group,
      entries: service.entries(group),
      query,
      results: searchResults(group.id, query),
      aiEnabled,
      replaces: service.customWordsSpelledLike(word)[0],
      ...extra,
    })
  }

  function renderCustomWords(extra: Partial<Parameters<typeof customWordsPage>[0]> = {}): SafeHtml {
    return customWordsPage({
      words: service.listCustomWords(),
      groupsByWord: service.groupsByCustomWord(),
      aiEnabled,
      replaces: extra.draft ? service.customWordsSpelledLike(extra.draft.word)[0] : undefined,
      ...extra,
    })
  }

  /** 同じ綴りの同梱語があれば案内する（allowDuplicate=1 で押し切れる） */
  function duplicateOf(form: URLSearchParams, addAction?: string): DuplicateHint | undefined {
    if (field(form, 'allowDuplicate') === '1') return undefined
    const hit = bundled.findBySpelling(field(form, 'word'))
    return hit ? { bundled: hit, addAction } : undefined
  }

  // --- ルート ---

  return [
    { method: 'GET', pattern: '/admin', handler: () => redirect('/admin/groups', 302) },

    // グループ一覧
    {
      method: 'GET',
      pattern: '/admin/groups',
      handler: () => htmlPage(groupsPage({ groups: service.listGroups() })),
    },
    {
      method: 'POST',
      pattern: '/admin/groups',
      handler: withForm((form) => {
        try {
          const group = service.createGroup(field(form, 'name'))
          return redirect(groupPath(group.id))
        } catch (error) {
          if (!(error instanceof AdminInputError)) throw error
          return badRequest(groupsPage({ groups: service.listGroups(), error: error.message }))
        }
      }),
    },

    // グループ詳細
    {
      method: 'GET',
      pattern: '/admin/groups/:id',
      handler: guarded((_request, { params, url }) =>
        htmlPage(renderGroup(params.id, url.searchParams.get('q') ?? '')),
      ),
    },
    {
      method: 'POST',
      pattern: '/admin/groups/:id/rename',
      handler: withForm((form, _request, { params }) => {
        try {
          service.renameGroup(params.id, field(form, 'name'))
          return redirect(groupPath(params.id))
        } catch (error) {
          if (!(error instanceof AdminInputError)) throw error
          return badRequest(renderGroup(params.id, '', { renameError: error.message }))
        }
      }),
    },
    {
      method: 'POST',
      pattern: '/admin/groups/:id/delete',
      handler: withForm((_form, _request, { params }) => {
        service.deleteGroup(params.id)
        return redirect('/admin/groups')
      }),
    },
    {
      method: 'POST',
      pattern: '/admin/groups/:id/words',
      handler: withForm((form, _request, { params }) => {
        const query = field(form, 'q')
        // 検索結果でチェックした語をまとめて入れる（選んだ順。単語帳の語の案内からは 1 つだけ届く）
        const wordIds = form.getAll('wordId').filter((id) => id !== '')
        try {
          if (wordIds.length === 0) throw new AdminInputError('追加する単語を選んでください')
          service.addWords(params.id, wordIds)
        } catch (error) {
          if (!(error instanceof AdminInputError)) throw error
          return badRequest(renderGroup(params.id, query, { addError: error.message }))
        }
        const search = query.trim() === '' ? '#words' : `?q=${encodeURIComponent(query)}#add`
        return redirect(`${groupPath(params.id)}${search}`)
      }),
    },
    {
      method: 'POST',
      pattern: '/admin/groups/:id/words/:wordId/remove',
      handler: withForm((_form, _request, { params }) => {
        service.removeWord(params.id, params.wordId)
        return redirect(`${groupPath(params.id)}#words`)
      }),
    },
    {
      method: 'POST',
      pattern: '/admin/groups/:id/words/:wordId/move',
      handler: withForm((form, _request, { params }) => {
        const direction = field(form, 'direction')
        if (direction !== 'up' && direction !== 'down') return text('bad direction', 400)
        service.moveWord(params.id, params.wordId, direction as MoveDirection)
        return redirect(`${groupPath(params.id)}#words`)
      }),
    },
    {
      method: 'POST',
      pattern: '/admin/groups/:id/custom-words',
      handler: withForm((form, _request, { params }) => {
        const group = service.getGroup(params.id)
        const draft = draftFrom(form)
        // 出し直すときに検索結果も残す
        const query = field(form, 'q')
        try {
          validateDraft(draft)
          const duplicate = duplicateOf(form, `${groupPath(group.id)}/words`)
          if (duplicate) return badRequest(renderGroup(group.id, query, { draft, duplicate }))
          // 同じ綴りの自作語があれば置き換える（自作語は綴りごとに 1 つ）
          service.upsertCustomWord(draft, group.id)
          return redirect(`${groupPath(group.id)}#words`)
        } catch (error) {
          if (!(error instanceof AdminInputError)) throw error
          return badRequest(renderGroup(group.id, query, { draft, wordError: error.message }))
        }
      }),
    },

    // マイ単語
    {
      method: 'GET',
      pattern: CUSTOM_WORDS_PATH,
      handler: () => htmlPage(renderCustomWords()),
    },
    {
      method: 'POST',
      pattern: CUSTOM_WORDS_PATH,
      handler: withForm((form) => {
        const draft = draftFrom(form)
        try {
          validateDraft(draft)
          const duplicate = duplicateOf(form)
          if (duplicate) return badRequest(renderCustomWords({ draft, duplicate }))
          service.upsertCustomWord(draft)
          return redirect(CUSTOM_WORDS_PATH)
        } catch (error) {
          if (!(error instanceof AdminInputError)) throw error
          return badRequest(renderCustomWords({ draft, error: error.message }))
        }
      }),
    },
    {
      method: 'GET',
      pattern: `${CUSTOM_WORDS_PATH}/:id`,
      handler: guarded((_request, { params, url }) => {
        const word = service.getCustomWord(params.id)
        return htmlPage(
          customWordEditPage({
            word,
            groups: service.groupsByCustomWord().get(word.wordId) ?? [],
            back: safeBack(url.searchParams.get('back'), CUSTOM_WORDS_PATH),
          }),
        )
      }),
    },
    {
      method: 'POST',
      pattern: `${CUSTOM_WORDS_PATH}/:id`,
      handler: withForm((form, _request, { params }) => {
        const back = safeBack(form.get('back'), CUSTOM_WORDS_PATH)
        const draft = draftFrom(form)
        try {
          service.updateCustomWord(params.id, draft)
          return redirect(back)
        } catch (error) {
          if (!(error instanceof AdminInputError)) throw error
          const word = service.getCustomWord(params.id)
          return badRequest(
            customWordEditPage({
              word,
              groups: service.groupsByCustomWord().get(word.wordId) ?? [],
              back,
              draft,
              error: error.message,
            }),
          )
        }
      }),
    },
    {
      method: 'POST',
      pattern: `${CUSTOM_WORDS_PATH}/:id/delete`,
      handler: withForm((form, _request, { params }) => {
        if (!isCustomWordId(params.id)) throw new AdminNotFoundError('単語が見つかりません')
        service.deleteCustomWord(params.id)
        return redirect(safeBack(form.get('back'), CUSTOM_WORDS_PATH))
      }),
    },
  ]
}
