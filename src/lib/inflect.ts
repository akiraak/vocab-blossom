/**
 * 見出し語が例文中にどの語形で現れているかを探す。
 *
 * データ検証（例文が見出し語を含むか）と、穴埋めクイズ（例文中の該当語を空欄化する）の
 * 両方で使う。英語の活用は規則変化で大半を作れるので、規則変化ルール + 不規則変化表で照合する。
 */

const VOWELS = 'aeiou'

/** 句動詞で目的語が割り込める助詞（例: call you back） */
const PARTICLES = new Set([
  'up', 'down', 'back', 'around', 'on', 'off', 'in', 'out', 'over', 'away', 'through', 'along',
])

const ARTICLES = new Set(['a', 'an', 'the'])

/** 不規則変化（動詞・名詞・形容詞）。A1〜A2 で扱う範囲をカバーする */
const IRREGULAR: Record<string, string[]> = {
  be: ['am', 'is', 'are', 'was', 'were', 'been', 'being'],
  become: ['became', 'become'],
  begin: ['began', 'begun'],
  bite: ['bit', 'bitten'],
  blow: ['blew', 'blown'],
  break: ['broke', 'broken'],
  bring: ['brought'],
  build: ['built'],
  burn: ['burnt'],
  buy: ['bought'],
  catch: ['caught'],
  choose: ['chose', 'chosen'],
  come: ['came', 'come'],
  cost: ['cost'],
  cut: ['cut'],
  deal: ['dealt'],
  dig: ['dug'],
  do: ['does', 'did', 'done'],
  draw: ['drew', 'drawn'],
  dream: ['dreamt'],
  drink: ['drank', 'drunk'],
  drive: ['drove', 'driven'],
  eat: ['ate', 'eaten'],
  fall: ['fell', 'fallen'],
  feed: ['fed'],
  feel: ['felt'],
  fight: ['fought'],
  find: ['found'],
  fly: ['flew', 'flown'],
  forget: ['forgot', 'forgotten'],
  forgive: ['forgave', 'forgiven'],
  freeze: ['froze', 'frozen'],
  get: ['got', 'gotten'],
  give: ['gave', 'given'],
  go: ['goes', 'went', 'gone'],
  grow: ['grew', 'grown'],
  hang: ['hung'],
  have: ['has', 'had', 'having'],
  hear: ['heard'],
  hide: ['hid', 'hidden'],
  hit: ['hit'],
  hold: ['held'],
  hurt: ['hurt'],
  keep: ['kept'],
  know: ['knew', 'known'],
  lay: ['laid'],
  lead: ['led'],
  learn: ['learnt'],
  leave: ['left'],
  lend: ['lent'],
  let: ['let'],
  lie: ['lay', 'lain', 'lying'],
  light: ['lit'],
  lose: ['lost'],
  make: ['made'],
  mean: ['meant'],
  meet: ['met'],
  pay: ['paid'],
  put: ['put'],
  read: ['read'],
  ride: ['rode', 'ridden'],
  ring: ['rang', 'rung'],
  rise: ['rose', 'risen'],
  run: ['ran'],
  say: ['said'],
  see: ['saw', 'seen'],
  sell: ['sold'],
  send: ['sent'],
  set: ['set'],
  shake: ['shook', 'shaken'],
  shine: ['shone'],
  shoot: ['shot'],
  show: ['showed', 'shown'],
  shut: ['shut'],
  sing: ['sang', 'sung'],
  sit: ['sat'],
  sleep: ['slept'],
  smell: ['smelt'],
  speak: ['spoke', 'spoken'],
  spend: ['spent'],
  spread: ['spread'],
  stand: ['stood'],
  steal: ['stole', 'stolen'],
  stick: ['stuck'],
  swim: ['swam', 'swum'],
  take: ['took', 'taken'],
  teach: ['taught'],
  tell: ['told'],
  think: ['thought'],
  throw: ['threw', 'thrown'],
  understand: ['understood'],
  wake: ['woke', 'woken'],
  wear: ['wore', 'worn'],
  weep: ['wept'],
  win: ['won'],
  write: ['wrote', 'written'],
  // 不規則な名詞の複数形
  child: ['children'],
  grandchild: ['grandchildren'],
  schoolchild: ['schoolchildren'],
  foot: ['feet'],
  goose: ['geese'],
  man: ['men'],
  mouse: ['mice'],
  person: ['people'],
  tooth: ['teeth'],
  woman: ['women'],
  fish: ['fish'],
  sheep: ['sheep'],
  // 不規則な比較級
  good: ['better', 'best'],
  bad: ['worse', 'worst'],
  far: ['farther', 'further'],
  little: ['less', 'least'],
  many: ['more', 'most'],
  much: ['more', 'most'],
}

function endsWithConsonantY(word: string): boolean {
  return word.length > 1 && word.endsWith('y') && !VOWELS.includes(word[word.length - 2])
}

/** 短母音 + 子音で終わり、語末子音を重ねる語（stop → stopped、big → bigger） */
function doublesFinalConsonant(word: string): boolean {
  if (word.length < 3) return false
  const [c3, c2, c1] = [word[word.length - 3], word[word.length - 2], word[word.length - 1]]
  return !VOWELS.includes(c1) && !'wxy'.includes(c1) && VOWELS.includes(c2) && !VOWELS.includes(c3)
}

/** 1 語の取りうる語形（原形 + 規則変化 + 不規則変化）をすべて返す */
export function wordForms(word: string): Set<string> {
  const base = word.toLowerCase()
  const forms = new Set<string>([base])

  if (endsWithConsonantY(base)) {
    const stem = base.slice(0, -1)
    for (const suffix of ['ies', 'ied', 'ier', 'iest', 'ily']) forms.add(stem + suffix)
  }
  if (/(s|x|z|ch|sh|o)$/.test(base)) forms.add(base + 'es')
  for (const suffix of ['s', 'ed', 'ing', 'er', 'est', 'ly', 'd', 'r', 'st']) forms.add(base + suffix)
  if (base.endsWith('e')) {
    const stem = base.slice(0, -1)
    for (const suffix of ['ing', 'ed', 'er', 'est', 'y']) forms.add(stem + suffix)
  }
  if (base.endsWith('fe')) forms.add(base.slice(0, -2) + 'ves')
  else if (base.endsWith('f')) forms.add(base.slice(0, -1) + 'ves')
  if (doublesFinalConsonant(base)) {
    const doubled = base + base[base.length - 1]
    for (const suffix of ['ed', 'ing', 'er', 'est']) forms.add(doubled + suffix)
  }
  for (const form of IRREGULAR[base] ?? []) forms.add(form)

  return forms
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function formsPattern(word: string): string {
  // 長い語形から先に試して、短い語形での部分一致に負けないようにする
  const forms = [...wordForms(word)].sort((a, b) => b.length - a.length)
  return `(?:${forms.map(escapeRegExp).join('|')})`
}

/**
 * 見出し語（複数語の熟語も可）の正規表現を組み立てる。
 *
 * - 先頭語と末尾語は活用形を許容する（went fishing / board games）
 * - 途中の冠詞は省略・変化を許容する（make a mistake → makes mistakes）
 * - 「動詞 + 助詞」の 2 語句は間に目的語が割り込める（call back → call you back）
 */
function headwordPattern(headword: string): string {
  const tokens = headword.toLowerCase().split(/\s+/)
  if (tokens.length === 1) return formsPattern(tokens[0])
  if (tokens.length === 2 && PARTICLES.has(tokens[1])) {
    return `${formsPattern(tokens[0])}\\s+(?:[\\w']+\\s+){0,2}${formsPattern(tokens[1])}`
  }

  const tokenPattern = (index: number) =>
    index === tokens.length - 1 ? formsPattern(tokens[index]) : escapeRegExp(tokens[index])

  let pattern = formsPattern(tokens[0])
  for (let i = 1; i < tokens.length; i++) {
    if (ARTICLES.has(tokens[i]) && i < tokens.length - 1) {
      // 冠詞は省略・変化を許容する（make a mistake → makes mistakes）
      pattern += `\\s+(?:(?:a|an|the)\\s+)?${tokenPattern(i + 1)}`
      i++
      continue
    }
    pattern += `\\s+${tokenPattern(i)}`
  }
  return pattern
}

export interface HeadwordMatch {
  /** 例文中で実際に使われている語形 */
  surface: string
  start: number
  end: number
}

/** 例文中の見出し語（活用形を含む）を探す。見つからなければ null */
export function findHeadword(sentence: string, headword: string): HeadwordMatch | null {
  const regex = new RegExp(`(?<![A-Za-z])${headwordPattern(headword)}(?![A-Za-z])`, 'i')
  const match = regex.exec(sentence)
  if (!match) return null
  return { surface: match[0], start: match.index, end: match.index + match[0].length }
}
