#!/usr/bin/env python3
"""String Catalogの未翻訳チェック(CLAUDE.md ローカライズ必須ルールの検証)。

全キーが対応言語(ja以外の6言語)の翻訳を持つことを確認する。
未翻訳・stale・フォーマット指定子の不一致があれば非0終了。
実行: python3 tools/check_localizations.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    ROOT / "app/MHSimulator/MHSimulator/Localizable.xcstrings",
    ROOT / "app/MHSimulator/MHSimulator/InfoPlist.xcstrings",
]
LANGS = ["en", "fr", "de", "es", "pt-BR", "ko"]

SPEC_RE = re.compile(r"%(?:\d+\$)?(?:@|lld|lf|d|f)")


def specs(text):
    return sorted(SPEC_RE.findall(re.sub(r"%%", "", text)))


def check(path):
    errors = []
    data = json.loads(path.read_text(encoding="utf-8"))
    for key, entry in data.get("strings", {}).items():
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        # ja(ソース言語)の値。無ければキー自体がソース文字列
        ja_value = locs.get("ja", {}).get("stringUnit", {}).get("value", key)
        expected = specs(ja_value)
        for lang in LANGS:
            unit = locs.get(lang, {}).get("stringUnit")
            if not unit or unit.get("state") not in ("translated", "needs_review"):
                errors.append(f"{path.name}: {key!r} → {lang} が未翻訳")
                continue
            # 位置指定(%1$@)は非位置(%@)と等価に扱って個数・種類を比較
            def normalize(items):
                return sorted(re.sub(r"%\d+\$", "%", s) for s in items)
            if normalize(specs(unit["value"])) != normalize(expected):
                errors.append(
                    f"{path.name}: {key!r} → {lang} のフォーマット指定子が不一致")
        if entry.get("extractionState") == "stale":
            errors.append(f"{path.name}: {key!r} はコードから参照されていない(stale)")
    return errors


def main():
    all_errors = []
    for path in CATALOGS:
        if not path.exists():
            all_errors.append(f"カタログが見つかりません: {path}")
            continue
        all_errors.extend(check(path))
    if all_errors:
        print(f"ローカライズチェック失敗({len(all_errors)}件):")
        for e in all_errors:
            print(f"  - {e}")
        sys.exit(1)
    print("ローカライズチェックOK(全キーが6言語の翻訳を保持)")


if __name__ == "__main__":
    main()
