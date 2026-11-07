import { describe, expect, it } from 'vitest'
import { escapeHtml, html, layout, raw } from './html.ts'

describe('html', () => {
  it('埋め込む値をエスケープする', () => {
    const meaning = '<script>alert("x")</script>'
    const example = `Tom's & "Jerry"`
    expect(html`<td>${meaning}</td><td title="${example}">${example}</td>`.value).toBe(
      '<td>&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;</td>' +
        '<td title="Tom&#39;s &amp; &quot;Jerry&quot;">Tom&#39;s &amp; &quot;Jerry&quot;</td>',
    )
  })

  it('入れ子の html と raw はそのまま、配列はつなげる', () => {
    const items = ['<a>', 'b'].map((w) => html`<li>${w}</li>`)
    expect(html`<ul>${items}</ul>${raw('<hr>')}`.value).toBe(
      '<ul><li>&lt;a&gt;</li><li>b</li></ul><hr>',
    )
  })

  it('null / undefined / false は空、数値は文字列にする', () => {
    expect(html`${null}${undefined}${false}${0}${12}`.value).toBe('012')
  })

  it('escapeHtml', () => {
    expect(escapeHtml(`&<>"'`)).toBe('&amp;&lt;&gt;&quot;&#39;')
  })

  it('layout はタイトルもエスケープする', () => {
    const page = layout({ title: '<b>グループ</b>', body: html`<p>本文</p>` }).value
    expect(page).toContain('<title>&lt;b&gt;グループ&lt;/b&gt; | VocabGarden 管理</title>')
    expect(page).toContain('<p>本文</p>')
    expect(page.startsWith('<!doctype html>')).toBe(true)
  })
})

describe('layout の JS', () => {
  it('構文エラーにならない', () => {
    const page = layout({ title: 't', nav: 'groups', body: html`` }).value
    const script = page.split('<script>')[1].split('</script>')[0]
    expect(() => new Function(script)).not.toThrow()
  })
})
