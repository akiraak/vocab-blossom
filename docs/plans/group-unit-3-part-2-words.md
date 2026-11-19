# グループ「Unit 3 Part 2」を作って 12 語を入れる

## 目的・背景

本番に新しいグループ「Unit 3 Part 2」を作り、次の 12 語を入れる（2026-11-19 の依頼）。

reluctantly, demand, persistence, a wide range of, restricted, uncomfortable, blunt, ignite, confidently, weakness, exceptionally, introverted

## 対応方針

- 手順は「Unit 3 Part 1」のとき（[group-unit-3-part-1-words](archive/group-unit-3-part-1-words.md)）と同じ。
  下書きは `data/groups/unit-3-part-2.json`、取り込みは `server/src/import-groups.ts`
- 本番に「Unit 3 Part 2」というグループは無いので、取り込みで新しく作る（2026-11-19 に本番 DB を読み取りで確認）
- 単語帳にある語はその ID を入れる: uncomfortable（a2-1150「心地よくない」）
- 残りの 11 語はマイ単語として作る。本番に同じ綴りのマイ単語は無い（同じく確認）
- demand は動詞「（強く）要求する」と名詞「要求、需要」の 2 つの意味を持たせる

## Step

1. 下書きを作ってチェックする（見出し語が例文にちょうど 1 回 = `countHeadword`、JSON の形）
2. 本番に取り込む: DB をバックアップ → `--dry-run` → 取り込み → もう一度 `--dry-run` で 0 件 → DB で 12 語を確認
3. iPhone で同期して確認（ユーザー）

## 影響範囲

- 追加: `data/groups/unit-3-part-2.json`。コードは変えない（サーバーの再デプロイも不要）
- 本番 DB: グループ「Unit 3 Part 2」が増え（12 語）、マイ単語が 11 語増える。取り消すときは管理画面で消す

## テスト方針

- 上のチェックと本番での `--dry-run`（トランザクションを取り消すので書き込まない）

## 結果

- Step 1（2026-11-19）: 見出し語は 11 語（demand は 2 つの意味とも）例文にちょうど 1 回。JSON の形も通った
- Step 2（2026-11-19）: DB をバックアップ（`/home/ubuntu/vocab-blossom/server/data/backup-20261119-before-unit-3-part-2-words.db`）
  → `--dry-run`（グループを作る 1・語を足す 12・マイ単語を作る 11・置き換える 0）→ 取り込み（同じ結果）
  → もう一度 `--dry-run` で 0 件 → 本番 DB で「Unit 3 Part 2」に 12 語が並びどおり入ったことを確認（マイ単語 108 → 119、グループ 14 → 15）
