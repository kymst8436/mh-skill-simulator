#!/usr/bin/env python3
"""抽選規則→あり得る鑑定護石の全列挙(検証用生成物。Q-2の規模実測)。

bundled.db の規則テーブル(CharmSkillGroup / CharmPattern)を読み、
data/generated/enumerated.db に EnumeratedCharm を生成する。

2026-08-22決定: 全列挙はアプリに同梱しない(153MBでサイズ予算50MBを超過するため)。
アプリは規則テーブルから実行時計算する。このスクリプトの生成物は
規則データの検証(実物護石との突き合わせ)とパイプラインの回帰テストに使う。

同一スキルは1つの護石に重複しない(ユーザー実機確認 2026-08-22)ため、
既定のdup-policyはdrop。--dup-policy keepで字義どおりの列挙にも切り替えられる。
"""
import argparse
import itertools
import json
import sqlite3
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BUNDLED_PATH = ROOT / "data" / "generated" / "bundled.db"
OUT_PATH = ROOT / "data" / "generated" / "enumerated.db"

OUT_SCHEMA = """
CREATE TABLE EnumeratedCharm (
  id INTEGER PRIMARY KEY,
  rarity INTEGER NOT NULL CHECK (rarity BETWEEN 5 AND 8),
  skill1Id INTEGER NOT NULL,
  skill1Level INTEGER NOT NULL,
  skill2Id INTEGER,
  skill2Level INTEGER,
  skill3Id INTEGER,
  skill3Level INTEGER,
  weaponSlots TEXT NOT NULL,
  armorSlots TEXT NOT NULL
);
CREATE INDEX idx_enumcharm_skill1 ON EnumeratedCharm(skill1Id);
CREATE INDEX idx_enumcharm_skill2 ON EnumeratedCharm(skill2Id);
CREATE INDEX idx_enumcharm_skill3 ON EnumeratedCharm(skill3Id);
CREATE TABLE Meta (
  charmRulesVersion TEXT NOT NULL,
  dupPolicy TEXT NOT NULL
);
"""


def load_rules(db):
    groups = {}
    for gid, skill_id, level in db.execute(
            "SELECT groupId, skillId, level FROM CharmSkillGroup ORDER BY groupId"):
        groups.setdefault(gid, []).append((skill_id, level))
    patterns = []
    for pid, rarity, g1, g2, g3 in db.execute(
            "SELECT id, rarity, skill1Group, skill2Group, skill3Group FROM CharmPattern"):
        combos = db.execute(
            "SELECT weaponSlots, armorSlots FROM CharmPatternSlotCombo WHERE patternId = ?",
            (pid,)).fetchall()
        patterns.append((rarity, g1, g2, g3, combos))
    if not groups or not patterns:
        raise SystemExit("bundled.dbに規則テーブルがありません。convert.pyを先に実行してください")
    return groups, patterns


def enumerate_charms(groups, patterns, dup_policy):
    seen = set()
    dup_skill_count = 0
    for rarity, g1, g2, g3, combos in patterns:
        s1_list = groups[g1]
        s2_list = groups[g2] if g2 else [None]
        s3_list = groups[g3] if g3 else [None]
        for s1, s2, s3 in itertools.product(s1_list, s2_list, s3_list):
            ids = [x[0] for x in (s1, s2, s3) if x]
            if len(ids) != len(set(ids)):
                dup_skill_count += 1
                if dup_policy == "drop":
                    continue
            for wslots, aslots in combos:
                seen.add((
                    rarity,
                    s1[0], s1[1],
                    s2[0] if s2 else None, s2[1] if s2 else None,
                    s3[0] if s3 else None, s3[1] if s3 else None,
                    wslots, aslots,
                ))
    return seen, dup_skill_count


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dup-policy", choices=["keep", "drop"], default="drop",
                        help="護石内の同一スキル重複を含めるか(既定drop。2026-08-22ユーザー確認)")
    args = parser.parse_args()

    src = sqlite3.connect(f"file:{BUNDLED_PATH}?mode=ro", uri=True)
    groups, patterns = load_rules(src)
    rules_version = src.execute("SELECT charmRulesVersion FROM Meta").fetchone()[0]
    src.close()

    t0 = time.time()
    charms, dup_skill_count = enumerate_charms(groups, patterns, args.dup_policy)
    t_enum = time.time() - t0

    if OUT_PATH.exists():
        OUT_PATH.unlink()
    db = sqlite3.connect(OUT_PATH)
    db.executescript(OUT_SCHEMA)
    with db:
        db.executemany(
            "INSERT INTO EnumeratedCharm VALUES (?,?,?,?,?,?,?,?,?,?)",
            ((i + 1, *c) for i, c in enumerate(sorted(charms))))
        db.execute("INSERT INTO Meta VALUES (?,?)", (rules_version, args.dup_policy))

    # --- ログ出力(Q-2実測) ---
    total = len(charms)
    print(f"全列挙完了: {total:,}件(列挙 {t_enum:.1f}s、dup-policy={args.dup_policy})")
    print(f"  同一スキル重複を含むスキル構成: {dup_skill_count:,}件"
          f"({'含めた' if args.dup_policy == 'keep' else '除外した'})")
    for rarity, count in db.execute(
            "SELECT rarity, COUNT(*) FROM EnumeratedCharm GROUP BY rarity"):
        print(f"  レア度{rarity}: {count:,}件")
    two = db.execute(
        "SELECT COUNT(*) FROM EnumeratedCharm WHERE skill2Id IS NOT NULL AND skill3Id IS NULL"
    ).fetchone()[0]
    three = db.execute(
        "SELECT COUNT(*) FROM EnumeratedCharm WHERE skill3Id IS NOT NULL").fetchone()[0]
    print(f"  スキル1のみ: {total - two - three:,} / 2スキル: {two:,} / 3スキル: {three:,}")
    print(f"  enumerated.db: {OUT_PATH.stat().st_size / 1024 / 1024:.1f} MB(アプリ非同梱)")
    print(f"  bundled.db: {BUNDLED_PATH.stat().st_size / 1024 / 1024:.1f} MB(アプリ同梱)")

    sample_id = db.execute("SELECT skill1Id FROM EnumeratedCharm LIMIT 1").fetchone()[0]
    t0 = time.time()
    hit = db.execute(
        "SELECT COUNT(*) FROM EnumeratedCharm"
        " WHERE skill1Id = ? OR skill2Id = ? OR skill3Id = ?",
        (sample_id, sample_id, sample_id)).fetchone()[0]
    print(f"  逆引きサンプルクエリ: {hit:,}件ヒット / {(time.time() - t0) * 1000:.0f}ms")
    db.close()


if __name__ == "__main__":
    main()
