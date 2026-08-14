#!/usr/bin/env python3
"""CEFR-J Wordlist Ver1.6 の xlsx から A1 / A2 の headword リストを TSV に抽出する。

出典: 『CEFR-J Wordlist Version 1.6』東京外国語大学投野由紀夫研究室
      http://www.cefr-j.org/download.html より 2026-08-13 取得

使い方:
    python3 extract-cefrj.py <CEFR-J Wordlist xlsx のパス> <出力ディレクトリ>

- 同一 headword が複数品詞で重複する場合は最初の行（リスト順）を採用する
- A1 と A2 の両方に載る headword は A1 側のみに採用する（アプリでは 1 語 1 エントリ）
- "a.m./A.M./am/AM" のようなスラッシュ区切りの表記ゆれは先頭の形を採用する
- 純粋な機能語（冠詞・代名詞・be 動詞など、クイズにならない語）は除外する
"""

import sys
import csv
from pathlib import Path

import openpyxl

# クイズとして成立しない純粋な機能語（アプリのデッキから除外する）
FUNCTION_WORDS = {
    "a", "an", "the",
    "i", "you", "he", "she", "it", "we", "they",
    "me", "him", "her", "us", "them",
    "my", "your", "his", "its", "our", "their",
    "mine", "yours", "hers", "ours", "theirs",
    "myself", "yourself", "himself", "herself", "itself",
    "ourselves", "yourselves", "themselves",
    "this", "that", "these", "those",
    "be", "am", "is", "are", "was", "were", "being", "been",
    "do", "does", "did", "doing", "done",
    "has", "had", "having",
    "'m", "'re", "'s", "'ll", "'ve", "'d", "n't", "not",
    "and", "or", "but",
    "to", "of",
}

# アプリ内で使う品詞名への正規化
POS_MAP = {
    "modal auxiliary": "modal",
    "be-verb": "verb",
    "do-verb": "verb",
    "have-verb": "verb",
}

# 複数品詞で載っている語のうち、リスト先頭の品詞が初学者に教える代表品詞として
# 不適切なものの上書き（例: catch はリスト上 noun が先だが動詞「捕まえる」で教える）
PRIMARY_POS = {
    "call": "verb", "catch": "verb", "change": "verb", "check": "verb",
    "climb": "verb", "cook": "verb", "cross": "verb", "cry": "verb",
    "dance": "verb", "drink": "verb", "drive": "verb", "finish": "verb",
    "fly": "verb", "hold": "verb", "hurry": "verb", "kick": "verb",
    "look": "verb", "love": "verb", "miss": "verb", "move": "verb",
    "need": "verb", "offer": "verb", "pack": "verb", "paint": "verb",
    "pass": "verb", "pay": "verb", "play": "verb", "rent": "verb",
    "repair": "verb", "return": "verb", "ride": "verb", "run": "verb",
    "spell": "verb", "stand": "verb", "start": "verb", "stop": "verb",
    "surf": "verb", "swim": "verb", "throw": "verb", "try": "verb",
    "turn": "verb", "visit": "verb", "walk": "verb", "wash": "verb",
    "watch": "verb", "wish": "verb", "work": "verb", "worry": "verb",
    "ring": "noun", "step": "noun",
    "fix": "verb", "float": "verb", "fry": "verb", "lead": "verb",
    "mention": "verb", "weep": "verb",
    "lyric": "noun", "license": "noun", "net": "noun", "uniform": "noun",
    # 単一品詞でもリストの品詞が不適切な語
    "dig": "verb", "feed": "verb", "hope": "verb", "shake": "verb",
    "touch": "verb", "wake": "verb",
    "bye": "interjection", "hello": "interjection",
    "key": "noun",
}

# 表記の正規化（大文字の敬称 Miss として載っているが、動詞 miss として採用する）
WORD_CANON = {"Miss": "miss"}


def extract(sheet, seen):
    rows = []
    for headword, pos, cefr, *_ in sheet.iter_rows(min_row=2, values_only=True):
        if not headword:
            continue
        word = str(headword).split("/")[0].strip()
        word = WORD_CANON.get(word, word)
        if word.lower() in FUNCTION_WORDS:
            continue
        if word.lower() in seen:
            continue
        seen.add(word.lower())
        pos = POS_MAP.get(str(pos or ""), str(pos or ""))
        pos = PRIMARY_POS.get(word.lower(), pos)
        rows.append((word, pos, str(cefr or "")))
    return rows


def main():
    xlsx_path, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    wb = openpyxl.load_workbook(xlsx_path, read_only=True)
    seen = set()
    for level in ("A1", "A2"):
        rows = extract(wb[level], seen)
        out = out_dir / f"cefrj-{level.lower()}.tsv"
        with out.open("w", newline="") as f:
            writer = csv.writer(f, delimiter="\t", lineterminator="\n")
            writer.writerow(["word", "pos", "level"])
            writer.writerows(rows)
        print(f"{out}: {len(rows)} words")


if __name__ == "__main__":
    main()
