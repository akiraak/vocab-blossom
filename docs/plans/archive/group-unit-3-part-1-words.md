# グループ「Unit 3 Part 1」に 11 語を足す

## 目的・背景

ユーザーが本番で作った空のグループ「Unit 3 Part 1」に、次の 11 語を足す（2026-11-12 の依頼）。

injuries, determined, recover, empower, reputation, punish, feel responsible, prohibit, meanwhile, regret, anonymous

## 対応方針

- 手順は「11-05」のとき（[group-11-05-words](archive/group-11-05-words.md)）と同じ。下書きは `data/groups/unit-3-part-1.json`、
  取り込みは `server/src/import-groups.ts`（同じ名前のグループがあればそれに足す）
- 単語帳にある語はその ID を足す: regret（a2-0876「後悔する」）
- meanwhile は本番に同じ綴りのマイ単語がある（「つなぎ言葉・時 2」で使用）。中身を同じにして、そのマイ単語をそのまま足す
- injuries は見出し語を単数形の injury にしたマイ単語として作る（単語帳にあるのは動詞 injure「けがをさせる」だけ）
- 残り（determined, recover, empower, reputation, punish, feel responsible, prohibit, anonymous）はマイ単語として作る。
  本番に同じ綴りのマイ単語は無い（2026-11-12 に本番 DB を読み取りで確認）

## Step

1. 下書きを作ってチェックする（見出し語が例文にちょうど 1 回 = `countHeadword`、JSON の形）
2. 本番に取り込む: DB をバックアップ → `--dry-run` → 取り込み → もう一度 `--dry-run` で 0 件 → DB で 11 語を確認
3. iPhone で同期して確認（ユーザー）

## 影響範囲

- 追加: `data/groups/unit-3-part-1.json`。コードは変えない（サーバーの再デプロイも不要）
- 本番 DB: グループ「Unit 3 Part 1」に 11 語、マイ単語が 9 語増える。取り消すときは管理画面で外す・消す

## テスト方針

- 上のチェックと本番での `--dry-run`（トランザクションを取り消すので書き込まない）

## 結果

- Step 1（2026-11-12）: 見出し語は 10 語とも例文にちょうど 1 回。JSON の形も通った
- Step 2（2026-11-12）: DB をバックアップ（`/home/ubuntu/vocab-blossom/server/data/backup-20261112-before-unit-3-part-1-words.db`）
  → `--dry-run`（既存の「Unit 3 Part 1」に足す 11・マイ単語を作る 9・置き換える 0）→ 取り込み（同じ結果）
  → もう一度 `--dry-run` で 0 件 → 本番 DB で「Unit 3 Part 1」に 11 語が並びどおり入ったことを確認（マイ単語 98 → 107、グループは 14 のまま）
- Step 3（2026-11-12）: ユーザーが iPhone で同期して確認した
