export const DAY_MS = 24 * 60 * 60 * 1000

/** その日の 0 時（ローカル時刻）の ms */
export function startOfDay(ms: number): number {
  const d = new Date(ms)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

/** 日付をまたぐ加算。DST を考慮して Date の日付操作で行う */
export function addDays(ms: number, days: number): number {
  const d = new Date(ms)
  d.setDate(d.getDate() + days)
  return d.getTime()
}

/** 進捗ログのキーに使う YYYY-MM-DD（ローカル時刻） */
export function dateKey(ms: number): string {
  const d = new Date(ms)
  const month = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${month}-${day}`
}

/** from → to の日数差（日付単位）。to が未来なら正 */
export function daysBetween(fromMs: number, toMs: number): number {
  return Math.round((startOfDay(toMs) - startOfDay(fromMs)) / DAY_MS)
}

/** 次回復習日の表示用ラベル */
export function formatDueLabel(dueAt: number, now: number): string {
  const diff = daysBetween(now, dueAt)
  if (diff <= 0) return '今日'
  if (diff === 1) return '明日'
  if (diff < 30) return `${diff}日後`
  const d = new Date(dueAt)
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

export function formatDate(ms: number): string {
  const d = new Date(ms)
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`
}
