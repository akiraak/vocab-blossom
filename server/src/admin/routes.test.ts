import { describe, expect, it } from 'vitest'
import { SyncStore } from '../sync/store.ts'
import { adminPost, createTestApp, req } from '../test-helpers.ts'
import { FORM_BODY_LIMIT, safeBack } from './routes.ts'

function setup() {
  const app = createTestApp()
  const store = new SyncStore(app.db)
  const page = async (path: string) => {
    const res = await app.handle(req(path))
    return { status: res.status, body: await res.text() }
  }
  const createGroup = async (name: string) => {
    const res = await app.handle(adminPost('/admin/groups', { name }))
    expect(res.status).toBe(303)
    const location = res.headers.get('location') ?? ''
    return { id: location.replace('/admin/groups/', ''), path: location }
  }
  const createWord = async (groupPath: string, fields: Record<string, string>) =>
    app.handle(adminPost(`${groupPath}/custom-words`, { pos: 'noun', ...fields }))
  return { ...app, store, page, createGroup, createWord }
}

describe('グループ一覧', () => {
  it('空のとき案内を出す', async () => {
    const { page } = setup()
    const { status, body } = await page('/admin/groups')
    expect(status).toBe(200)
    expect(body).toContain('<h1>グループ</h1>')
    expect(body).toContain('グループはまだありません')
    expect(body).toContain('aria-current="page"')
  })

  it('追加すると詳細へ 303、一覧に名前と語数が出る', async () => {
    const { page, createGroup, handle } = setup()
    const { id, path } = await createGroup('旅行')
    expect(path).toMatch(/^\/admin\/groups\/[0-9a-f-]{36}$/)
    await handle(adminPost(`${path}/words`, { wordId: 'a1-0001' }))

    const { body } = await page('/admin/groups')
    expect(body).toContain(`<a href="/admin/groups/${id}">旅行</a>`)
    expect(body).toMatch(/<td class="num">1<\/td>/)
  })

  it('削除すると一覧へ戻る（削除の確認つき）', async () => {
    const { page, createGroup, handle, store } = setup()
    const { id, path } = await createGroup('旅行')
    expect((await page('/admin/groups')).body).toContain('data-confirm="グループ「旅行」を削除しますか？')

    const res = await handle(adminPost(`${path}/delete`))
    expect(res.status).toBe(303)
    expect(res.headers.get('location')).toBe('/admin/groups')
    expect(store.getGroup(id)).toBeNull()
  })
})

describe('グループ詳細', () => {
  it('無いグループ・UUID でない ID は 404', async () => {
    const { page, handle } = setup()
    expect((await page('/admin/groups/00000000-0000-0000-0000-000000000000')).status).toBe(404)
    expect((await page('/admin/groups/nope')).status).toBe(404)
    expect((await handle(adminPost('/admin/groups/nope/rename', { name: 'x' }))).status).toBe(404)
  })

  it('名前の変更', async () => {
    const { createGroup, handle, store } = setup()
    const { id, path } = await createGroup('旅行')
    const res = await handle(adminPost(`${path}/rename`, { name: '出張' }))
    expect(res.status).toBe(303)
    expect(store.getGroup(id)?.name).toBe('出張')
  })

  it('検索して追加すると、検索語を残して戻り「追加済み」になる', async () => {
    const { page, createGroup, handle, store } = setup()
    const { id, path } = await createGroup('旅行')

    const search = await page(`${path}?q=get%20up`)
    expect(search.body).toContain('get up')
    expect(search.body).toContain('name="wordId" value="ph-0001"')

    const res = await handle(adminPost(`${path}/words`, { wordId: 'ph-0001', q: 'get up' }))
    expect(res.status).toBe(303)
    expect(res.headers.get('location')).toBe(`${path}?q=get%20up#add`)
    expect(store.getGroup(id)?.wordIds).toEqual(['ph-0001'])

    const after = await page(`${path}?q=get%20up`)
    expect(after.body).toContain('追加済み')
  })

  it('見つからない検索語ではマイ単語を作る案内を出す', async () => {
    const { page, createGroup } = setup()
    const { path } = await createGroup('旅行')
    expect((await page(`${path}?q=zzzqqq`)).body).toContain('「zzzqqq」は単語帳にありません')
  })

  it('単語を追加は 1 セクション: 検索語が無ければ作成フォームを出さず、あれば結果の下に検索語入りで出す', async () => {
    const { page, createGroup } = setup()
    const { path } = await createGroup('旅行')
    const empty = await page(path)
    expect(empty.body).toContain('id="add"')
    expect(empty.body).not.toContain('単語帳から追加')
    expect(empty.body).not.toContain(`action="${path}/custom-words"`)

    const found = await page(`${path}?q=get%20up`)
    expect(found.body).toContain(`action="${path}/custom-words"`)
    expect(found.body).toContain('「get up」をマイ単語として作る')
    expect(found.body).toContain('name="q" value="get up"')
  })

  it('検索結果でチェックした語をまとめて追加する（選んだ順）。1 つも選ばなければ 400', async () => {
    const { createGroup, handle, store } = setup()
    const { id, path } = await createGroup('旅行')
    const res = await handle(
      adminPost(`${path}/words`, [
        ['q', 'a'],
        ['wordId', 'a1-0002'],
        ['wordId', 'a1-0001'],
      ]),
    )
    expect(res.status).toBe(303)
    expect(store.getGroup(id)?.wordIds).toEqual(['a1-0002', 'a1-0001'])

    const none = await handle(adminPost(`${path}/words`, { q: 'a' }))
    expect(none.status).toBe(400)
    expect(await none.text()).toContain('追加する単語を選んでください')
  })

  it('検索は完全一致を先頭にし、グループに入っているマイ単語も「追加済み」で出す', async () => {
    const { page, createGroup, createWord, store } = setup()
    const { id, path } = await createGroup('学校')
    await createWord(path, { word: 'homeroom', meaning: 'ホームルーム' })
    const [wordId] = store.getGroup(id)?.wordIds ?? []

    const search = await page(`${path}?q=homeroom#add`)
    const row = search.body.slice(search.body.indexOf('data-pick-form'))
    expect(row).toContain('homeroom<span class="tag custom">マイ単語</span>')
    expect(row).toContain('追加済み')
    expect(row).not.toContain(`value="${wordId}"`)

    // home は完全一致が先（homework などの前方一致より前）
    const home = await page(`${path}?q=home`)
    const table = home.body.slice(home.body.indexOf('data-pick-form'))
    const first = table.match(/name="wordId" value="([^"]+)"> ([^<]+)</)
    expect(first?.[2]).toBe('home')
  })

  it('同じ綴りのマイ単語があれば、作ると置き換えになると伝え、作っても 1 つのまま', async () => {
    const { page, createGroup, createWord, store } = setup()
    const { id, path } = await createGroup('学校')
    await createWord(path, { word: 'commute', meaning: '通勤する', pos: 'verb' })
    const notice = await page(`${path}?q=commute`)
    expect(notice.body).toContain('「commute」（通勤する）はマイ単語にあります')

    const res = await createWord(path, { word: 'Commute', meaning: '通勤', q: 'commute' })
    expect(res.status).toBe(303)
    const words = store.listCustomWords()
    expect(words).toHaveLength(1)
    expect(words[0]).toMatchObject({ word: 'Commute', meaning: '通勤' })
    expect(store.getGroup(id)?.wordIds).toEqual([words[0].wordId])
  })

  it('存在しない語の追加は 400', async () => {
    const { createGroup, handle } = setup()
    const { path } = await createGroup('旅行')
    const res = await handle(adminPost(`${path}/words`, { wordId: 'zz-0001' }))
    expect(res.status).toBe(400)
    expect(await res.text()).toContain('追加できない単語です')
  })

  it('外す・並べ替え', async () => {
    const { createGroup, handle, store } = setup()
    const { id, path } = await createGroup('旅行')
    for (const wordId of ['a1-0001', 'a1-0002', 'a1-0003']) {
      await handle(adminPost(`${path}/words`, { wordId }))
    }
    expect((await handle(adminPost(`${path}/words/a1-0003/move`, { direction: 'up' }))).status).toBe(303)
    expect(store.getGroup(id)?.wordIds).toEqual(['a1-0001', 'a1-0003', 'a1-0002'])
    expect((await handle(adminPost(`${path}/words/a1-0001/move`, { direction: 'left' }))).status).toBe(400)

    expect((await handle(adminPost(`${path}/words/a1-0003/remove`))).status).toBe(303)
    expect(store.getGroup(id)?.wordIds).toEqual(['a1-0001', 'a1-0002'])
  })
})

describe('自作語の作成（グループ詳細）', () => {
  it('作ってグループに入れ、マイ単語の印と編集リンクが出る', async () => {
    const { page, createGroup, createWord, store } = setup()
    const { id, path } = await createGroup('学校')
    const res = await createWord(path, { word: 'homeroom', meaning: 'ホームルーム' })
    expect(res.status).toBe(303)

    const [wordId] = store.getGroup(id)?.wordIds ?? []
    expect(wordId).toMatch(/^custom-/)
    const { body } = await page(path)
    expect(body).toContain('homeroom<span class="tag custom">マイ単語</span>')
    expect(body).toContain(`/admin/custom-words/${wordId}?back=`)
  })

  it('必須が空なら 400 で入力を残して出し直す', async () => {
    const { createGroup, createWord, store } = setup()
    const { path } = await createGroup('学校')
    const res = await createWord(path, { word: 'homeroom', meaning: ' ', example: 'We have homeroom.' })
    expect(res.status).toBe(400)
    const body = await res.text()
    expect(body).toContain('意味を入れてください')
    expect(body).toContain('value="homeroom"')
    expect(body).toContain('>We have homeroom.</textarea>')
    expect(store.listCustomWords()).toEqual([])
  })

  it('同じ綴りの同梱語があれば案内し、押し切れば作る', async () => {
    const { createGroup, createWord, store } = setup()
    const { id, path } = await createGroup('学校')

    const res = await createWord(path, { word: ' Action ', meaning: 'アクション（映画）' })
    expect(res.status).toBe(400)
    const body = await res.text()
    expect(body).toContain('「action」（行動）は単語帳にあります')
    expect(body).toContain('単語帳の「action」を追加する')
    expect(body).toContain('name="allowDuplicate" value="1"')
    expect(body).toContain('それでも自作語として作る')
    expect(store.listCustomWords()).toEqual([])

    const forced = await createWord(path, { word: 'Action', meaning: 'アクション（映画）', allowDuplicate: '1' })
    expect(forced.status).toBe(303)
    expect(store.listCustomWords().map((w) => w.word)).toEqual(['Action'])
    expect(store.getGroup(id)?.wordIds).toHaveLength(1)
  })
})

describe('マイ単語', () => {
  it('グループに入れずに作り、一覧に入っているグループが出る', async () => {
    const { page, createGroup, createWord, handle } = setup()
    const { path } = await createGroup('学校')
    await createWord(path, { word: 'homeroom', meaning: 'ホームルーム' })
    const res = await handle(adminPost('/admin/custom-words', { word: 'lunchbox', meaning: '弁当箱', pos: 'noun' }))
    expect(res.status).toBe(303)
    expect(res.headers.get('location')).toBe('/admin/custom-words')

    const { body } = await page('/admin/custom-words')
    expect(body).toContain('lunchbox')
    expect(body).toMatch(/homeroom<\/a><\/td>[\s\S]*?<a href="\/admin\/groups\/[^"]+">学校<\/a>/)
    expect(body).toMatch(/lunchbox<\/a><\/td>[\s\S]*?<span class="muted">なし<\/span>/)
  })

  it('編集して戻り先へ戻る。外のパスには戻さない', async () => {
    const { page, createGroup, createWord, handle, store } = setup()
    const { id, path } = await createGroup('学校')
    await createWord(path, { word: 'homeroom', meaning: 'ホームルーム' })
    const [wordId] = store.getGroup(id)?.wordIds ?? []

    const edit = await page(`/admin/custom-words/${wordId}?back=${encodeURIComponent(path)}`)
    expect(edit.status).toBe(200)
    expect(edit.body).toContain(`name="back" value="${path}"`)

    const res = await handle(
      adminPost(`/admin/custom-words/${wordId}`, {
        word: 'homeroom',
        meaning: '朝の会',
        pos: 'noun',
        back: path,
      }),
    )
    expect(res.status).toBe(303)
    expect(res.headers.get('location')).toBe(path)
    expect(store.getCustomWord(wordId)?.meaning).toBe('朝の会')

    const evil = await handle(
      adminPost(`/admin/custom-words/${wordId}`, {
        word: 'homeroom',
        meaning: '朝の会',
        pos: 'noun',
        back: 'https://evil.example/',
      }),
    )
    expect(evil.headers.get('location')).toBe('/admin/custom-words')
  })

  it('意味を複数入れて作り、一覧に品詞ごとの意味が出る。編集で意味を消せる', async () => {
    const { page, handle, store } = setup()
    const res = await handle(
      adminPost('/admin/custom-words', [
        ['word', 'commute'],
        ['meaning', '通勤する'],
        ['pos', 'verb'],
        ['example', ''],
        ['exampleJa', ''],
        ['extraMeaning', '通勤'],
        ['extraPos', 'noun'],
        ['extraExample', 'My commute is long.'],
        ['extraExampleJa', ''],
        // 意味を足すための空の欄
        ['extraMeaning', ''],
        ['extraPos', 'adjective'],
        ['extraExample', ''],
        ['extraExampleJa', ''],
      ]),
    )
    expect(res.status).toBe(303)
    const [word] = store.listCustomWords()
    expect(word.extraSenses).toEqual([{ pos: 'noun', meaning: '通勤', example: 'My commute is long.', exampleJa: '' }])

    const list = await page('/admin/custom-words')
    expect(list.body).toContain('動詞: 通勤する／名詞: 通勤')
    expect(list.body).toContain('動詞・名詞')

    const edit = await page(`/admin/custom-words/${word.wordId}`)
    expect(edit.body).toContain('意味 2')
    expect(edit.body).toContain('name="extraRemove" value="0"')
    // 空の欄の品詞は、まだ使っていない品詞（名詞・動詞の次の形容詞）
    expect(edit.body).toMatch(/<option value="adjective" selected>/)

    const removed = await handle(
      adminPost(`/admin/custom-words/${word.wordId}`, [
        ['word', 'commute'],
        ['meaning', '通勤する'],
        ['pos', 'verb'],
        ['extraMeaning', '通勤'],
        ['extraPos', 'noun'],
        ['extraExample', ''],
        ['extraExampleJa', ''],
        ['extraRemove', '0'],
      ]),
    )
    expect(removed.status).toBe(303)
    expect(store.getCustomWord(word.wordId)?.extraSenses).toEqual([])
  })

  it('意味が複数の自作語は、グループ詳細の一覧・検索結果にも品詞ごとの意味が出る', async () => {
    const { page, createGroup, handle, store } = setup()
    const { path } = await createGroup('学校')
    await handle(
      adminPost('/admin/custom-words', [
        ['word', 'commute'],
        ['meaning', '通勤する'],
        ['pos', 'verb'],
        ['extraMeaning', '通勤'],
        ['extraPos', 'noun'],
      ]),
    )
    const [word] = store.listCustomWords()
    // 2 つ目の意味でも検索できる
    const search = await page(`${path}?q=${encodeURIComponent('通勤')}`)
    expect(search.body).toContain('動詞: 通勤する／名詞: 通勤')

    await handle(adminPost(`${path}/words`, { wordId: word.wordId }))
    const detail = await page(path)
    expect(detail.body).toContain('動詞: 通勤する／名詞: 通勤')
  })

  it('編集で必須が空なら 400', async () => {
    const { createGroup, createWord, handle, store } = setup()
    const { id, path } = await createGroup('学校')
    await createWord(path, { word: 'homeroom', meaning: 'ホームルーム' })
    const [wordId] = store.getGroup(id)?.wordIds ?? []
    const res = await handle(adminPost(`/admin/custom-words/${wordId}`, { word: '', meaning: 'x', pos: 'noun' }))
    expect(res.status).toBe(400)
    expect(await res.text()).toContain('英語を入れてください')
  })

  it('削除するとグループからも外れる', async () => {
    const { createGroup, createWord, handle, store } = setup()
    const { id, path } = await createGroup('学校')
    await handle(adminPost(`${path}/words`, { wordId: 'a1-0001' }))
    await createWord(path, { word: 'homeroom', meaning: 'ホームルーム' })
    const wordId = store.getGroup(id)?.wordIds[1] ?? ''

    const res = await handle(adminPost(`/admin/custom-words/${wordId}/delete`, { back: path }))
    expect(res.status).toBe(303)
    expect(res.headers.get('location')).toBe(path)
    expect(store.getCustomWord(wordId)).toBeNull()
    expect(store.getGroup(id)?.wordIds).toEqual(['a1-0001'])
  })

  it('無い自作語は 404', async () => {
    const { page, handle } = setup()
    expect((await page('/admin/custom-words/custom-nope')).status).toBe(404)
    expect((await page('/admin/custom-words/a1-0001')).status).toBe(404)
    expect((await handle(adminPost('/admin/custom-words/a1-0001/delete'))).status).toBe(404)
  })
})

describe('安全性', () => {
  it('グループ名・単語・意味に入れた HTML はエスケープされる', async () => {
    const { page, createGroup, createWord, store } = setup()
    const xss = '<script>alert(1)</script>'
    const { id, path } = await createGroup(`"><img src=x onerror=alert(1)>`)
    await createWord(path, { word: xss, meaning: xss, example: xss, exampleJa: xss })
    const [wordId] = store.getGroup(id)?.wordIds ?? []

    for (const p of ['/admin/groups', path, `${path}?q=${encodeURIComponent(xss)}`, '/admin/custom-words', `/admin/custom-words/${wordId}`]) {
      const { body } = await page(p)
      expect(body, p).not.toContain('<script>alert(1)')
      expect(body, p).not.toContain('<img src=x')
    }
    expect((await page(path)).body).toContain('&lt;script&gt;alert(1)&lt;/script&gt;')
  })

  it('Origin の無い POST は 403（何も保存しない）', async () => {
    const { handle, store } = setup()
    const res = await handle(req('/admin/groups', { method: 'POST', body: 'name=x' }))
    expect(res.status).toBe(403)
    expect(store.listGroups()).toEqual([])
  })

  it('フォームの本文が大きすぎれば 413', async () => {
    const { handle } = setup()
    const res = await handle(adminPost('/admin/groups', { name: 'a'.repeat(FORM_BODY_LIMIT + 1) }))
    expect(res.status).toBe(413)
  })

  it('safeBack は管理画面の中のパスだけ通す', () => {
    expect(safeBack('/admin/groups/x', '/f')).toBe('/admin/groups/x')
    for (const value of [null, '', 'https://evil.example', '//evil.example', '/admin\\@evil', '/other']) {
      expect(safeBack(value, '/f'), String(value)).toBe('/f')
    }
  })
})
