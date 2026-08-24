#!/usr/bin/env python3
"""MHW_Icons_SVG(MIT)から武器種・防具部位・護石アイコンを取り込む。

- 入力: MHW_Icons_SVG リポジトリのローカルclone(引数で指定)
- 出力: app/MHSimulator/MHSimulator/Assets.xcassets/Icons/ 配下のimageset群
- 再着色: 元SVGはランク色のグレー2〜3階調。DESIGN.mdのトーンに置換する
  (明部 → mhTextSecondary #A89F87 / 暗部 → mhTextTertiary #6F675A)

使い方:
  python3 tools/icons/import_icons.py /path/to/MHW_Icons_SVG
"""
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSETS = REPO_ROOT / "app/MHSimulator/MHSimulator/Assets.xcassets/Icons"

# 明暗のしきい値(輝度160)。元SVGのfillはグレースケールのみ
LIGHT = "rgb(168,159,135)"  # mhTextSecondary #A89F87
DARK = "rgb(111,103,90)"    # mhTextTertiary #6F675A

# 取り込み対象: (アセット名, リポジトリ内SVGパス)。ランクは形が同じなのでRank_01を使う
SOURCES = {
    "weapon_great-sword": "SVG/Weapons/Great_Sword/Great_Sword_Rank_01.svg",
    "weapon_long-sword": "SVG/Weapons/Long_Sword/Long_Sword_Rank_01.svg",
    "weapon_sword-shield": "SVG/Weapons/Sword_&_Shield/Sword_&_Shield_Rank_01.svg",
    "weapon_dual-blades": "SVG/Weapons/Dual_Blades/Dual_Blades_Rank_01.svg",
    "weapon_hammer": "SVG/Weapons/Hammer/Hammer_Rank_01.svg",
    "weapon_hunting-horn": "SVG/Weapons/Hunting_Horn/Hunting_Horn_Rank_01.svg",
    "weapon_lance": "SVG/Weapons/Lance/Lance_Rank_01.svg",
    "weapon_gunlance": "SVG/Weapons/Gunlance/Gunlance_Rank_01.svg",
    "weapon_switch-axe": "SVG/Weapons/Switch_Axe/Switch_Axe_Rank_01.svg",
    "weapon_charge-blade": "SVG/Weapons/Charge_Blade/Charge_Blade_Rank_01.svg",
    "weapon_insect-glaive": "SVG/Weapons/Insect_Glaive/Insect_Glaive_Rank_01.svg",
    "weapon_bow": "SVG/Weapons/Bow/Bow_Rank_01.svg",
    "weapon_heavy-bowgun": "SVG/Weapons/Heavy_Bowgun/Heavy_Bowgun_Rank_01.svg",
    "weapon_light-bowgun": "SVG/Weapons/Light_Bowgun/Light_Bowgun_Rank_01.svg",
    # 防具部位。リポジトリの Chest=胴(メイル)、Torso=腰(コイル)であることを目視確認済み(2026-08-24)
    "piece_head": "SVG/Hunter/Helm/Helm_Rank_01.svg",
    "piece_chest": "SVG/Hunter/Chest/Chest_Rank_01.svg",
    "piece_arms": "SVG/Hunter/Arms/Arms_Rank_01.svg",
    "piece_waist": "SVG/Hunter/Torso/Torso_Rank_01.svg",
    "piece_legs": "SVG/Hunter/Legs/Legs_Rank_01.svg",
    "icon_charm": "SVG/Hunter/Charm/Charm_Rank_01.svg",
}

FILL_RE = re.compile(r"fill:rgb\((\d+),(\d+),(\d+)\)")


def recolor(svg: str) -> str:
    def repl(m: re.Match) -> str:
        r, g, b = (int(m.group(i)) for i in (1, 2, 3))
        luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return f"fill:{LIGHT if luminance >= 160 else DARK}"

    return FILL_RE.sub(repl, svg)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    src_repo = Path(sys.argv[1])
    if not (src_repo / "LICENSE").exists():
        print(f"error: {src_repo} はMHW_Icons_SVGのcloneではありません")
        return 1

    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    for name, rel in SOURCES.items():
        svg_path = src_repo / rel
        svg = svg_path.read_text(encoding="utf-8")
        colors = set(FILL_RE.findall(svg))
        for r, g, b in colors:
            if r != g or g != b:
                print(f"warning: {rel} に非グレーの色 rgb({r},{g},{b})")
        imageset = ASSETS / f"{name}.imageset"
        imageset.mkdir(exist_ok=True)
        (imageset / f"{name}.svg").write_text(recolor(svg), encoding="utf-8")
        (imageset / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True},
        }, indent=2) + "\n")

    print(f"ok: {len(SOURCES)}件のimagesetを {ASSETS} に生成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
