#!/usr/bin/env python3
"""レビュー結果（修正提案 JSON）をデッキ JSON に適用する。

使い方:
    python3 scripts/apply-review.py <提案ファイル|ディレクトリ> [...]

提案は `{"id", "field", "old", "new", "reason"}` の配列。
`meaning` / `example` / `exampleJa` 以外のフィールドは受け付けない（id は学習進捗のキーで不変）。
`old` が現在値と一致しない提案はスキップし、末尾に一覧を出す（重複適用の防止）。
"""

import json
import sys
from glob import glob
from pathlib import Path

DECK_DIR = Path("src/data/decks")
EDITABLE = {"meaning", "example", "exampleJa"}


def load_proposals(paths: list[str]) -> list[dict]:
    files: list[Path] = []
    for path in paths:
        p = Path(path)
        files.extend(sorted(p.glob("*.json")) if p.is_dir() else [p])

    proposals = []
    for f in files:
        try:
            data = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            print(f"!! {f.name}: JSON として読めない ({e})")
            continue
        if not isinstance(data, list):
            print(f"!! {f.name}: 配列ではない")
            continue
        for item in data:
            item["_src"] = f.name
            proposals.append(item)
    return proposals


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    proposals = load_proposals(sys.argv[1:])
    decks = {p: json.loads(Path(p).read_text()) for p in sorted(glob(str(DECK_DIR / "*.json")))}
    index = {w["id"]: w for deck in decks.values() for w in deck["words"]}

    applied, skipped = 0, []
    for item in proposals:
        wid, field, new = item.get("id"), item.get("field"), item.get("new")
        src = item.get("_src")
        if field not in EDITABLE:
            skipped.append(f"{wid} {field}: 変更できないフィールド ({src})")
            continue
        word = index.get(wid)
        if word is None:
            skipped.append(f"{wid}: 存在しない ID ({src})")
            continue
        if not isinstance(new, str) or not new.strip():
            skipped.append(f"{wid} {field}: new が空 ({src})")
            continue
        if "old" in item and word[field] != item["old"]:
            skipped.append(f"{wid} {field}: old が現在値と不一致 ({src})")
            continue
        if word[field] == new:
            continue
        word[field] = new
        applied += 1

    for path, deck in decks.items():
        Path(path).write_text(json.dumps(deck, ensure_ascii=False, indent=2) + "\n")

    print(f"提案 {len(proposals)} 件 / 適用 {applied} 件 / スキップ {len(skipped)} 件")
    for line in skipped:
        print("  skip:", line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
