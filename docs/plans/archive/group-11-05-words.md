# グループ「11-05」に 9 語を足す

## 目的・背景

ユーザーが本番で作った空のグループ「11-05」（2026-11-05 作成）に、次の 9 語を足す（2026-11-05 の依頼）。

adjust to, adapt, custom, isolated, confident, open-minded, stereotype, respect, point of view

## 対応方針

- 単語帳にある語はその ID を足す: custom（a2-0285「習慣／風習」）、confident（a2-0242「自信のある」）
- adjust は単語帳にあるが「調節する」（a2-0014）で意味が違うので、adjust to は「〜に慣れる」のマイ単語（熟語）として作る
- 残りの 7 語（adjust to, adapt, isolated, open-minded, stereotype, respect, point of view）はマイ単語として作る。
  本番に同じ綴りのマイ単語は無い（2026-11-05 に `/api/sync` で確認）
- respect は動詞「尊重する」と名詞「敬意」の 2 つの意味にする
- 下書きは `data/groups/11-05.json`。取り込みは connective-groups と同じ `server/src/import-groups.ts` を使う
  （同じ名前のグループがあればそれに足すので、既存の「11-05」に入る）

## Step

1. 下書き（`data/groups/11-05.json`）を作ってチェックし、ユーザーに確認してもらう
   - チェック: 例文の語数・見出し語がちょうど 1 回（`countHeadword`）・単語帳の意味と重ならない・使い捨て DB での `--dry-run`
2. 本番に取り込む: DB をバックアップ → `--dry-run` → 取り込み → `/api/sync` で「11-05」に 9 語が入ったことを確認
3. iPhone で同期して確認（ユーザー）

## 影響範囲

- 追加: `data/groups/11-05.json`。コードは変えない（サーバーの再デプロイも不要）
- 本番 DB: グループ「11-05」に 9 語、マイ単語が 7 語増える。取り消すときは管理画面で外す・消す

## テスト方針

- 上のチェックと `--dry-run`。内容はユーザーが目で確認する

## 結果

- Step 1（2026-11-05）: チェックはすべて通った。使い捨て DB の `--dry-run` で「作る 1・足す 9・マイ単語を作る 7」。ユーザーが内容を確認した
- Step 2（2026-11-05）: 取り込む前に DB をバックアップ（`/home/ubuntu/vocab-blossom/server/data/backup-20261105-before-11-05-words.db`）
  → `--dry-run`（既存の「11-05」に足す 9・マイ単語を作る 7）→ 取り込み（同じ結果）→ もう一度 `--dry-run` で 0 件
  → コンテナ内から `POST /api/sync`: グループ 13・マイ単語 98（91 + 7）、「11-05」に 9 語が並びどおり入り、respect は意味 2 つ
- Step 3（2026-11-05）: ユーザーが iPhone で同期して「11-05」の 9 語を確認した
