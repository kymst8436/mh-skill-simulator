#!/usr/bin/env python3
"""Nettogeの鑑定護石ページから抽選規則を機械的に写経するスクリプト(Q-1)。

ページ内のインラインJS(GROUP_SKILLS)とHTMLパターン表を正規表現で抽出し、
data/charm-rules/charm-rules.json を生成する。**内容の推測・補完は行わない**。
抽出できない構造変化があればエラーで停止する。

スロット記法(ページ凡例より):
- レア度5〜7: 数字列は防具スロットのサイズ列。0はスロットなしの埋め字
- レア度8: 先頭桁は武器スロット(スロ1固定)、残りが防具スロット
- 例(レア度8): "111" = 武器スロ①+防具スロ①×2

実行: python3 tools/enumerate-charms/extract_rules.py [--html 保存済みHTML]
"""
import argparse
import datetime
import html as htmllib
import json
import re
import sys
import urllib.request
from pathlib import Path

SOURCE_URL = "https://nettoge.com/mhwilds-talisman-patterns-simulator/"
ROOT = Path(__file__).resolve().parent.parent.parent
OUT_PATH = ROOT / "data" / "charm-rules" / "charm-rules.json"

EXPECTED_GROUP_IDS = set(range(1, 11))


class ExtractError(Exception):
    pass


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return res.read().decode("utf-8")


def extract_groups(page):
    m = re.search(r"GROUP_SKILLS\s*=\s*\{(.*?)\n\s*\};", page, re.S)
    if not m:
        raise ExtractError("GROUP_SKILLSが見つかりません(ページ構造が変わった可能性)")
    groups = {}
    for gm in re.finditer(r"(\d+):\s*\[(.*?)\]", m.group(1), re.S):
        gid = int(gm.group(1))
        skills = [
            {"name": htmllib.unescape(n), "level": int(lv)}
            for n, lv in re.findall(r'\{name:"([^"]+)",level:(\d+)\}', gm.group(2))
        ]
        if not skills:
            raise ExtractError(f"グループ{gid}のスキルが抽出できません")
        groups[gid] = skills
    if set(groups.keys()) != EXPECTED_GROUP_IDS:
        raise ExtractError(f"グループIDが想定(1..10)と不一致: {sorted(groups.keys())}")
    return groups


def parse_slot_combo(code, rarity):
    if not re.fullmatch(r"\d{2,3}", code):
        raise ExtractError(f"スロット記号が想定外: {code!r} (レア度{rarity})")
    digits = [int(d) for d in code]
    if rarity == 8:
        # 先頭桁=武器スロット(スロ1固定)
        if digits[0] != 1:
            raise ExtractError(f"レア度8の先頭桁が武器スロ1でない: {code!r}")
        weapon = [1]
        armor = [d for d in digits[1:] if d != 0]
    else:
        weapon = []
        armor = [d for d in digits if d != 0]
    return {"code": code, "weaponSlots": weapon, "armorSlots": armor}


def extract_patterns(page):
    m = re.search(r"<table.*?</table>", page, re.S)
    if not m:
        raise ExtractError("パターン表(table)が見つかりません")
    patterns = []
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", m.group(0), re.S)
    for row in rows:
        cells = [
            htmllib.unescape(re.sub(r"<[^>]+>", "", c)).strip()
            for c in re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", row, re.S)
        ]
        if len(cells) != 5 or cells[0] == "レア度":
            continue
        rarity_m = re.fullmatch(r"レア度(\d)", cells[0])
        if not rarity_m:
            raise ExtractError(f"レア度セルが想定外: {cells[0]!r}")
        rarity = int(rarity_m.group(1))

        def group_or_none(cell):
            if cell in ("–", "-", "—", ""):
                return None
            if not cell.isdigit():
                raise ExtractError(f"グループセルが想定外: {cell!r}")
            return int(cell)

        combos = [parse_slot_combo(c, rarity) for c in cells[4].split()]
        patterns.append({
            "rarity": rarity,
            "skill1Group": group_or_none(cells[1]),
            "skill2Group": group_or_none(cells[2]),
            "skill3Group": group_or_none(cells[3]),
            "slotCombos": combos,
        })
    if not patterns:
        raise ExtractError("パターン行が1件も抽出できません")
    return patterns


def validate(groups, patterns):
    for p in patterns:
        if p["skill1Group"] is None:
            raise ExtractError(f"skill1が空のパターンがあります: {p}")
        for key in ("skill1Group", "skill2Group", "skill3Group"):
            gid = p[key]
            if gid is not None and gid not in groups:
                raise ExtractError(f"パターンが未定義グループ{gid}を参照: {p}")
        if p["skill2Group"] is None and p["skill3Group"] is not None:
            raise ExtractError(f"skill2なしでskill3ありのパターン: {p}")
    rarities = {p["rarity"] for p in patterns}
    if rarities != {5, 6, 7, 8}:
        raise ExtractError(f"レア度の集合が想定(5..8)と不一致: {sorted(rarities)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--html", type=Path, help="保存済みHTMLから抽出(未指定なら実サイト取得)")
    args = parser.parse_args()

    page = args.html.read_text(encoding="utf-8") if args.html else fetch(SOURCE_URL)

    groups = extract_groups(page)
    patterns = extract_patterns(page)
    validate(groups, patterns)

    today = datetime.date.today().isoformat()
    rules = {
        "version": f"{today}.1",
        "source": {
            "url": SOURCE_URL,
            "extractedAt": today,
            "method": "ページ内インラインJS(GROUP_SKILLS)とHTMLパターン表の機械抽出",
            "note": "確率は取り込まない(決定済み)。実物護石との突き合わせ検証が済むまで実験的データ",
        },
        "slotNotation": {
            "rarity5to7": "数字列=防具スロットのサイズ列(0は埋め字)。武器スロットなし",
            "rarity8": "先頭桁=武器スロット(スロ1固定)、残り=防具スロット",
        },
        "resolvedQuestions": [
            "同一スキルは1つの護石に重複しない(ユーザー実機確認 2026-08-22)。列挙はdup-policy=dropで除外する",
            "レア度7にスロ3はあり得る(ユーザー実機確認 2026-08-22)。パターン表が正、ページ凡例の「スロ3はレア度5のみ」が誤り",
        ],
        "skillGroups": {str(k): v for k, v in sorted(groups.items())},
        "patterns": patterns,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(rules, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    total_skills = sum(len(v) for v in groups.values())
    print(f"抽出完了: {OUT_PATH}")
    print(f"  スキルグループ: {len(groups)}(延べ{total_skills}スキル)")
    print(f"  パターン行: {len(patterns)}")
    for r in (5, 6, 7, 8):
        n = sum(1 for p in patterns if p["rarity"] == r)
        print(f"    レア度{r}: {n}行")


if __name__ == "__main__":
    try:
        main()
    except ExtractError as e:
        print(f"抽出失敗: {e}", file=sys.stderr)
        sys.exit(1)
