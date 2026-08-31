#!/usr/bin/env python3
"""bundled.db の件数・整合性検証テスト(引き継ぎ§4 手順3)。

実測値(引き継ぎ§3.2、2026-08-21取得 commit c50a1eb8)をテストで固定する。
上流データ更新で件数が変わったら、意図的な更新であることを確認して期待値を改訂する。

実行: python3 tools/convert/test_convert.py
"""
import json
import sqlite3
import unittest
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "generated" / "bundled.db"


class TestBundledDb(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def count(self, sql):
        return self.db.execute(sql).fetchone()[0]

    # --- 件数の固定(引き継ぎ§3.2の実測値) ---

    def test_skill_count(self):
        self.assertEqual(self.count("SELECT COUNT(*) FROM Skill"), 179)

    def test_armor_counts(self):
        self.assertEqual(self.count("SELECT COUNT(*) FROM ArmorSeries"), 194)
        self.assertEqual(self.count("SELECT COUNT(*) FROM ArmorPiece"), 714)

    def test_decoration_count(self):
        self.assertEqual(self.count("SELECT COUNT(*) FROM Decoration"), 361)

    def test_fixed_charm_systems(self):
        # 固定護石は60系統(鑑定護石4系統はFixedCharmに入れない)
        self.assertEqual(self.count("SELECT COUNT(DISTINCT id) FROM FixedCharm"), 60)

    def test_weapon_count(self):
        self.assertEqual(self.count("SELECT COUNT(*) FROM Weapon"), 1188)
        self.assertEqual(self.count("SELECT COUNT(DISTINCT kind) FROM Weapon"), 14)

    def test_decoration_allowed_on_distribution(self):
        self.assertEqual(
            self.count("SELECT COUNT(*) FROM Decoration WHERE allowedOn='weapon'"), 295)
        self.assertEqual(
            self.count("SELECT COUNT(*) FROM Decoration WHERE allowedOn='armor'"), 66)

    def test_composite_decorations(self):
        # 2スキル持ち複合装飾品は173件
        composite = self.count(
            "SELECT COUNT(*) FROM (SELECT decorationId FROM DecorationSkill"
            " GROUP BY decorationId HAVING COUNT(*) = 2)")
        self.assertEqual(composite, 173)

    def test_skill_kind_distribution(self):
        rows = dict(self.db.execute("SELECT kind, COUNT(*) FROM Skill GROUP BY kind"))
        self.assertEqual(rows, {"armor": 71, "weapon": 66, "set": 25, "group": 17})

    # --- 整合性 ---

    def test_referential_integrity_skills(self):
        for table, col in [
            ("ArmorPieceSkill", "skillId"), ("DecorationSkill", "skillId"),
            ("FixedCharmSkill", "skillId"), ("WeaponSkill", "skillId"),
            ("ArmorSeries", "setBonusSkillId"), ("ArmorSeries", "groupBonusSkillId"),
        ]:
            orphans = self.count(
                f"SELECT COUNT(*) FROM {table} WHERE {col} IS NOT NULL"
                f" AND {col} NOT IN (SELECT id FROM Skill)")
            self.assertEqual(orphans, 0, f"{table}.{col} に孤児参照")

    def test_every_series_has_five_pieces_or_fewer(self):
        over = self.count(
            "SELECT COUNT(*) FROM (SELECT seriesId FROM ArmorPiece"
            " GROUP BY seriesId HAVING COUNT(*) > 5)")
        self.assertEqual(over, 0)

    def test_slots_are_valid_json_arrays(self):
        for (slots, lb_slots) in self.db.execute(
                "SELECT slots, limitBreakSlots FROM ArmorPiece"):
            for text in (slots, lb_slots):
                parsed = json.loads(text)
                self.assertIsInstance(parsed, list)
                self.assertLessEqual(len(parsed), 3)
                for s in parsed:
                    self.assertIn(s, (1, 2, 3))

    # --- 限界突破スロット(仕様4.1。レア5=全3スロ+1 / レア6=左2スロ+1 / 上限3) ---

    def test_limit_break_spot_checks(self):
        cases = [
            ("ホープマスクα", [1], [2, 1, 1]),        # レア5: 空き枠も①新設
            ("ミツネヘルムα", [3], [3, 1]),           # レア6: ③は上限で頭打ち
            ("ミツネヘルムβ", [3, 2], [3, 3]),        # レア6: 左2スロのみ
            ("鬼の数珠α", [2, 2, 1], [2, 2, 1]),      # 豪鬼α: 限界突破対象外
        ]
        for name, base, expected in cases:
            row = self.db.execute(
                "SELECT slots, limitBreakSlots FROM ArmorPiece WHERE nameJa = ?",
                (name,)).fetchone()
            self.assertIsNotNone(row, name)
            self.assertEqual(json.loads(row[0]), base, name)
            self.assertEqual(json.loads(row[1]), expected, name)

    def test_limit_break_unchanged_outside_rare_5_6(self):
        # レア5・6(豪鬼α除く)以外は slots と一致すること
        diff = self.count(
            "SELECT COUNT(*) FROM ArmorPiece p JOIN ArmorSeries s ON p.seriesId = s.id"
            " WHERE p.slots != p.limitBreakSlots"
            " AND (s.rarity NOT IN (5, 6) OR s.id = 3633)")
        self.assertEqual(diff, 0)

    def test_limit_break_matches_wikidb_harvest(self):
        # wiki-db実測381部位との突き合わせ(_meta.excluded は既知のwiki-db側ミス)
        fixture = json.loads(
            (Path(__file__).resolve().parent / "testdata"
             / "wikidb_limitbreak_slots.json").read_text(encoding="utf-8"))
        excluded = set(fixture["_meta"]["excluded"])
        by_name = dict(self.db.execute("SELECT nameJa, limitBreakSlots FROM ArmorPiece"))
        checked = 0
        for plus_name, value in fixture["slots"].items():
            if plus_name in excluded:
                continue
            base_name = plus_name[:-1]  # 末尾の「+」を除去
            self.assertIn(base_name, by_name, plus_name)
            expected = [int(x) for x in value.split("-") if x != "0"]
            self.assertEqual(json.loads(by_name[base_name]), expected, plus_name)
            checked += 1
        self.assertEqual(checked, 380)

    def test_fixed_charm_skill_count_per_rank(self):
        over = self.count(
            "SELECT COUNT(*) FROM (SELECT fixedCharmId, rankIndex FROM FixedCharmSkill"
            " GROUP BY fixedCharmId, rankIndex HAVING COUNT(*) > 2)")
        self.assertEqual(over, 0)

    def test_max_skill_level(self):
        self.assertLessEqual(self.count("SELECT MAX(maxLevel) FROM Skill"), 7)

    def test_spot_check_names(self):
        # 既知のスキル名が対応7言語すべてで引けること
        row = self.db.execute(
            "SELECT nameJa, nameEn, nameFr, nameDe, nameEs, namePtBr, nameKo"
            " FROM Skill WHERE id = -2125233152").fetchone()
        self.assertEqual(list(row), [
            "龍耐性", "Dragon Resistance", "Aura draconique",
            "Drachenwiderstand", "Antidraco", "Resistência a Dragão", "용 내성"])

    def test_no_missing_localized_names(self):
        # 全言語列がNOT NULLかつ非空(欠損はja埋めされるため空はデータ異常)
        for table in ("Skill", "ArmorSeries", "ArmorPiece", "Decoration",
                      "FixedCharm", "RandomCharm", "Weapon"):
            for col in ("nameJa", "nameEn", "nameFr", "nameDe",
                        "nameEs", "namePtBr", "nameKo"):
                empty = self.count(
                    f"SELECT COUNT(*) FROM {table} WHERE {col} IS NULL OR {col} = ''")
                self.assertEqual(empty, 0, f"{table}.{col} に空の名前")

    def test_random_charm_names(self):
        # 鑑定護石4系統(OCRアンカー用)
        self.assertEqual(self.count("SELECT COUNT(DISTINCT id) FROM RandomCharm"), 4)

    def test_meta(self):
        row = self.db.execute(
            "SELECT schemaVersion, sourceCommit FROM Meta").fetchone()
        self.assertEqual(row[0], 3)
        self.assertNotEqual(row[1], "unknown")

    # --- 抽選規則テーブル(2026-08-22改訂: アプリは規則から実行時計算する) ---

    def test_charm_rule_counts(self):
        # Nettoge写経の実測値: グループ10個・延べ288スキル・パターン29行
        self.assertEqual(self.count("SELECT COUNT(DISTINCT groupId) FROM CharmSkillGroup"), 10)
        self.assertEqual(self.count("SELECT COUNT(*) FROM CharmSkillGroup"), 288)
        self.assertEqual(self.count("SELECT COUNT(*) FROM CharmPattern"), 29)
        self.assertEqual(self.count("SELECT COUNT(*) FROM CharmPatternSlotCombo"), 100)

    def test_charm_rule_integrity(self):
        self.assertEqual(self.count(
            "SELECT COUNT(*) FROM CharmSkillGroup"
            " WHERE skillId NOT IN (SELECT id FROM Skill)"), 0)
        for col in ("skill1Group", "skill2Group", "skill3Group"):
            self.assertEqual(self.count(
                f"SELECT COUNT(*) FROM CharmPattern WHERE {col} IS NOT NULL"
                f" AND {col} NOT IN (SELECT DISTINCT groupId FROM CharmSkillGroup)"), 0)
        self.assertEqual(self.count(
            "SELECT COUNT(*) FROM CharmPattern"
            " WHERE id NOT IN (SELECT patternId FROM CharmPatternSlotCombo)"), 0)

    def test_charm_rules_version_set(self):
        version = self.db.execute("SELECT charmRulesVersion FROM Meta").fetchone()[0]
        self.assertNotEqual(version, "none")

    def test_bundled_db_within_app_size_budget(self):
        # アプリサイズ予算50MB(仕様6.1)に対する上流側ガード
        self.assertLess(DB_PATH.stat().st_size, 10 * 1024 * 1024)


ENUM_PATH = DB_PATH.parent / "enumerated.db"


@unittest.skipUnless(ENUM_PATH.exists(), "enumerated.db未生成(enumerate.pyを実行)")
class TestEnumeratedDb(unittest.TestCase):
    """検証用の全列挙DB(アプリ非同梱)。規則写経+dup-policy=dropの結果を固定する。"""

    @classmethod
    def setUpClass(cls):
        cls.db = sqlite3.connect(f"file:{ENUM_PATH}?mode=ro", uri=True)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_total_count(self):
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM EnumeratedCharm").fetchone()[0],
            2_076_040)

    def test_rarity_range(self):
        lo, hi = self.db.execute(
            "SELECT MIN(rarity), MAX(rarity) FROM EnumeratedCharm").fetchone()
        self.assertEqual((lo, hi), (5, 8))

    def test_no_duplicate_skill_within_charm(self):
        # 同一スキルは1つの護石に重複しない(2026-08-22ユーザー実機確認)
        dup = self.db.execute(
            "SELECT COUNT(*) FROM EnumeratedCharm"
            " WHERE skill1Id = skill2Id OR skill1Id = skill3Id"
            " OR (skill2Id IS NOT NULL AND skill2Id = skill3Id)").fetchone()[0]
        self.assertEqual(dup, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
