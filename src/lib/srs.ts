import { addDays, startOfDay } from './date'

export const MAX_STAGE = 5
export const MIN_LEARNED_STAGE = 1

/** ステージに到達したときの次回復習までの日数 */
const INTERVAL_DAYS: Record<number, number> = { 1: 1, 2: 3, 3: 7, 4: 14, 5: 30 }
/** 開花済みの単語を再度正解したときの維持間隔 */
const MAINTENANCE_DAYS = 90
/** 「もう知ってる」で押し上げるステージ */
const KNOWN_STAGE = 4

export interface SrsResult {
  stage: number
  dueAt: number
}

export function intervalDays(prevStage: number, nextStage: number): number {
  if (nextStage === MAX_STAGE && prevStage === MAX_STAGE) return MAINTENANCE_DAYS
  return INTERVAL_DAYS[nextStage] ?? 1
}

/**
 * 回答結果からステージと次回復習日を求める。
 * 未学習（stage 0）で不正解でも芽（1）にして翌日の復習に乗せる。
 */
export function applyAnswer(prevStage: number, correct: boolean, now: number): SrsResult {
  if (!correct) {
    const stage = Math.max(prevStage - 1, MIN_LEARNED_STAGE)
    return { stage, dueAt: startOfDay(addDays(now, 1)) }
  }
  const stage = Math.min(prevStage + 1, MAX_STAGE)
  return { stage, dueAt: startOfDay(addDays(now, intervalDays(prevStage, stage))) }
}

/** 「もう知ってる」を押されたとき */
export function applyKnown(now: number): SrsResult {
  return { stage: KNOWN_STAGE, dueAt: startOfDay(addDays(now, INTERVAL_DAYS[KNOWN_STAGE])) }
}

export type GrowthStage = 'seed' | 'sprout' | 'bud' | 'blossom'

export const GROWTH_LABEL: Record<GrowthStage, string> = {
  seed: '種',
  sprout: '芽',
  bud: 'つぼみ',
  blossom: '開花',
}

export function growthOf(stage: number): GrowthStage {
  if (stage <= 0) return 'seed'
  if (stage <= 2) return 'sprout'
  if (stage <= 4) return 'bud'
  return 'blossom'
}
