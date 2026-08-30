#!/usr/bin/env python3
"""JSON→SQLite変換パイプライン(仕様.md 3.4 / 4.1)。

data/source/merged/ のマージ済みJSONから data/generated/bundled.db を生成する。
検証失敗はビルド失敗として非0終了し、生成物を出さない。

id方針:
- 基本は game_id (Int32・負値あり) をそのまま主キーに使う
- ArmorPiece.id は seriesId * 8 + 部位index で導出(64bit演算。部位indexは KIND_INDEX)
- Weapon.id は (武器種index << 32) | (game_id & 0xFFFFFFFF)。
  game_idが武器種ごとの連番で全体では重複するため(実測: 1188本中ユニーク98)
"""
import argparse
import datetime
import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

SCHEMA_VERSION = 2

# 対応言語とSQLite列サフィックス(ja以外は欠損時jaへフォールバック)
LANGUAGES = [
    ("ja", "Ja"),
    ("en", "En"),
    ("fr", "Fr"),
    ("de", "De"),
    ("es", "Es"),
    ("pt-BR", "PtBr"),
    ("ko", "Ko"),
]

PIECE_KINDS = ["head", "chest", "arms", "waist", "legs"]

WEAPON_FILES = [
    "Bow", "ChargeBlade", "DualBlades", "GreatSword", "Gunlance", "Hammer",
    "HeavyBowgun", "HuntingHorn", "InsectGlaive", "Lance", "LightBowgun",
    "LongSword", "SwitchAxe", "SwordShield",
]

def _lang_cols(prefix, nullable=False):
    constraint = "" if nullable else " NOT NULL"
    return ",\n  ".join(f"{prefix}{suffix} TEXT{constraint}" for _, suffix in LANGUAGES)


def _ph(count):
    return ",".join(["?"] * count)


SCHEMA_SQL = f"""
CREATE TABLE Skill (
  id INTEGER PRIMARY KEY,
  {_lang_cols('name')},
  kind TEXT NOT NULL CHECK (kind IN ('armor','weapon','set','group')),
  maxLevel INTEGER NOT NULL,
  iconKind TEXT NOT NULL,
  iconId INTEGER NOT NULL,
  {_lang_cols('description', nullable=True)}
);
CREATE TABLE SkillRank (
  skillId INTEGER NOT NULL REFERENCES Skill(id),
  level INTEGER NOT NULL,
  {_lang_cols('effect')},
  PRIMARY KEY (skillId, level)
);
CREATE TABLE ArmorSeries (
  id INTEGER PRIMARY KEY,
  {_lang_cols('name')},
  rarity INTEGER NOT NULL,
  setBonusSkillId INTEGER REFERENCES Skill(id),
  groupBonusSkillId INTEGER REFERENCES Skill(id)
);
CREATE TABLE ArmorSeriesBonusRank (
  seriesId INTEGER NOT NULL REFERENCES ArmorSeries(id),
  bonusKind TEXT NOT NULL CHECK (bonusKind IN ('set','group')),
  pieces INTEGER NOT NULL,
  skillLevel INTEGER NOT NULL,
  PRIMARY KEY (seriesId, bonusKind, pieces)
);
CREATE TABLE ArmorPiece (
  id INTEGER PRIMARY KEY,
  seriesId INTEGER NOT NULL REFERENCES ArmorSeries(id),
  kind TEXT NOT NULL CHECK (kind IN ('head','chest','arms','waist','legs')),
  {_lang_cols('name')},
  defenseBase INTEGER NOT NULL,
  defenseMax INTEGER NOT NULL,
  resFire INTEGER NOT NULL,
  resWater INTEGER NOT NULL,
  resThunder INTEGER NOT NULL,
  resIce INTEGER NOT NULL,
  resDragon INTEGER NOT NULL,
  slots TEXT NOT NULL
);
CREATE TABLE ArmorPieceSkill (
  armorPieceId INTEGER NOT NULL REFERENCES ArmorPiece(id),
  skillId INTEGER NOT NULL REFERENCES Skill(id),
  level INTEGER NOT NULL,
  PRIMARY KEY (armorPieceId, skillId)
);
CREATE TABLE Decoration (
  id INTEGER PRIMARY KEY,
  {_lang_cols('name')},
  slotSize INTEGER NOT NULL CHECK (slotSize BETWEEN 1 AND 3),
  allowedOn TEXT NOT NULL CHECK (allowedOn IN ('weapon','armor')),
  rarity INTEGER NOT NULL,
  iconColor TEXT NOT NULL,
  iconColorId INTEGER NOT NULL
);
CREATE TABLE DecorationSkill (
  decorationId INTEGER NOT NULL REFERENCES Decoration(id),
  skillId INTEGER NOT NULL REFERENCES Skill(id),
  level INTEGER NOT NULL,
  PRIMARY KEY (decorationId, skillId)
);
CREATE TABLE FixedCharm (
  id INTEGER NOT NULL,
  rankIndex INTEGER NOT NULL,
  {_lang_cols('name')},
  rarity INTEGER NOT NULL,
  PRIMARY KEY (id, rankIndex)
);
CREATE TABLE RandomCharm (
  id INTEGER NOT NULL,
  rankIndex INTEGER NOT NULL,
  {_lang_cols('name')},
  rarity INTEGER NOT NULL,
  PRIMARY KEY (id, rankIndex)
);
CREATE TABLE FixedCharmSkill (
  fixedCharmId INTEGER NOT NULL,
  rankIndex INTEGER NOT NULL,
  skillId INTEGER NOT NULL REFERENCES Skill(id),
  level INTEGER NOT NULL,
  PRIMARY KEY (fixedCharmId, rankIndex, skillId)
);
CREATE TABLE Weapon (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL,
  {_lang_cols('name')},
  rarity INTEGER NOT NULL,
  attackRaw INTEGER NOT NULL,
  affinity INTEGER NOT NULL,
  slots TEXT NOT NULL,
  seriesId INTEGER
);
CREATE TABLE WeaponSkill (
  weaponId INTEGER NOT NULL REFERENCES Weapon(id),
  skillId INTEGER NOT NULL REFERENCES Skill(id),
  level INTEGER NOT NULL,
  PRIMARY KEY (weaponId, skillId)
);
CREATE TABLE CharmSkillGroup (
  groupId INTEGER NOT NULL,
  skillId INTEGER NOT NULL REFERENCES Skill(id),
  level INTEGER NOT NULL,
  PRIMARY KEY (groupId, skillId, level)
);
CREATE TABLE CharmPattern (
  id INTEGER PRIMARY KEY,
  rarity INTEGER NOT NULL CHECK (rarity BETWEEN 5 AND 8),
  skill1Group INTEGER NOT NULL,
  skill2Group INTEGER,
  skill3Group INTEGER
);
CREATE TABLE CharmPatternSlotCombo (
  patternId INTEGER NOT NULL REFERENCES CharmPattern(id),
  weaponSlots TEXT NOT NULL,
  armorSlots TEXT NOT NULL
);
CREATE INDEX idx_charmskillgroup_skill ON CharmSkillGroup(skillId);
CREATE INDEX idx_armorpieceskill_skill ON ArmorPieceSkill(skillId);
CREATE INDEX idx_decorationskill_skill ON DecorationSkill(skillId);
CREATE TABLE Meta (
  schemaVersion INTEGER NOT NULL,
  generatedAt TEXT NOT NULL,
  sourceCommit TEXT NOT NULL,
  charmRulesVersion TEXT NOT NULL
);
"""


class ValidationError(Exception):
    pass


def ja(names, context):
    text = (names or {}).get("ja")
    if not text:
        raise ValidationError(f"日本語名がありません: {context}")
    return text


def texts(names, context, required=True):
    """LANGUAGES順のテキストタプル。ja以外の欠損はjaで埋める(仕様: jaが正)。

    required=Falseはjaも欠けてよい(説明文など)。その場合の欠損はNone。
    """
    names = names or {}
    ja_text = names.get("ja")
    if required and not ja_text:
        raise ValidationError(f"日本語名がありません: {context}")
    return tuple(names.get(code) or ja_text for code, _ in LANGUAGES)


def effect_texts(descriptions):
    """SkillRank用: NOT NULL列のため欠損は空文字で埋める"""
    descriptions = descriptions or {}
    ja_text = descriptions.get("ja") or ""
    return tuple(descriptions.get(code) or ja_text for code, _ in LANGUAGES)


def read_source_commit(source_dir):
    source_md = source_dir / "SOURCE.md"
    if source_md.exists():
        m = re.search(r"commit:\s*([0-9a-f]{7,40})", source_md.read_text(encoding="utf-8"))
        if m:
            return m.group(1)
    return "unknown"


def load_json(source_dir, name):
    path = source_dir / "merged" / name
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def armor_piece_id(series_id, kind):
    return series_id * 8 + PIECE_KINDS.index(kind)


def weapon_id(kind_index, game_id):
    return (kind_index << 32) | (game_id & 0xFFFFFFFF)


def convert(source_dir, out_path):
    skills = load_json(source_dir, "Skill.json")
    armors = load_json(source_dir, "Armor.json")
    accessories = load_json(source_dir, "Accessory.json")
    amulets = load_json(source_dir, "Amulet.json")

    skill_ids = {s["game_id"] for s in skills}

    def require_skill(skill_id, context):
        if int(skill_id) not in skill_ids:
            raise ValidationError(f"skillId {skill_id} がSkillに存在しません: {context}")
        return int(skill_id)

    db = sqlite3.connect(":memory:")
    db.executescript(SCHEMA_SQL)

    # --- Skill / SkillRank ---
    for s in skills:
        name = ja(s["names"], f"Skill {s['game_id']}")
        names = texts(s["names"], f"Skill {s['game_id']}")
        descs = texts(s.get("descriptions"), None, required=False)
        ranks = s["ranks"]
        if not ranks:
            raise ValidationError(f"ranksが空です: Skill {name}")
        db.execute(
            f"INSERT INTO Skill VALUES ({_ph(5 + 2 * len(LANGUAGES))})",
            (s["game_id"], *names, s["kind"], len(ranks), s["icon"], s["icon_id"], *descs),
        )
        for r in ranks:
            effects = effect_texts(r.get("descriptions"))
            db.execute(
                f"INSERT INTO SkillRank VALUES ({_ph(2 + len(LANGUAGES))})",
                (s["game_id"], r["level"], *effects),
            )

    # --- ArmorSeries / ArmorPiece ---
    for series in armors:
        sid = series["game_id"]
        name = ja(series["names"], f"ArmorSeries {sid}")
        set_bonus = series.get("set_bonus")
        group_bonus = series.get("group_bonus")
        set_skill = require_skill(set_bonus["skill_id"], f"{name} set_bonus") if set_bonus else None
        group_skill = require_skill(group_bonus["skill_id"], f"{name} group_bonus") if group_bonus else None
        db.execute(
            f"INSERT INTO ArmorSeries VALUES ({_ph(4 + len(LANGUAGES))})",
            (sid, *texts(series["names"], f"ArmorSeries {sid}"),
             series["rarity"], set_skill, group_skill),
        )
        for bonus_kind, bonus in (("set", set_bonus), ("group", group_bonus)):
            if not bonus:
                continue
            # 上流データに完全重複エントリあり(ゴグα/β)。重複除去し、矛盾のみエラー
            levels_by_pieces = {}
            for rank in bonus["ranks"]:
                prev_level = levels_by_pieces.get(rank["pieces"])
                if prev_level is not None and prev_level != rank["skill_level"]:
                    raise ValidationError(
                        f"{name} {bonus_kind}_bonus: pieces={rank['pieces']} のskill_levelが矛盾"
                    )
                levels_by_pieces[rank["pieces"]] = rank["skill_level"]
            for pieces, skill_level in sorted(levels_by_pieces.items()):
                db.execute(
                    "INSERT INTO ArmorSeriesBonusRank VALUES (?,?,?,?)",
                    (sid, bonus_kind, pieces, skill_level),
                )
        for piece in series["pieces"]:
            kind = piece["kind"]
            if kind not in PIECE_KINDS:
                raise ValidationError(f"未知の部位kind: {kind} ({name})")
            pid = armor_piece_id(sid, kind)
            pname = ja(piece["names"], f"ArmorPiece {name}/{kind}")
            res = piece["resistances"]
            db.execute(
                f"INSERT INTO ArmorPiece VALUES ({_ph(11 + len(LANGUAGES))})",
                (
                    pid, sid, kind, *texts(piece["names"], f"ArmorPiece {name}/{kind}"),
                    piece["defense"]["base"], piece["defense"]["max"],
                    res["fire"], res["water"], res["thunder"], res["ice"], res["dragon"],
                    json.dumps(piece["slots"]),
                ),
            )
            for skill_id, level in (piece.get("skills") or {}).items():
                db.execute(
                    "INSERT INTO ArmorPieceSkill VALUES (?,?,?)",
                    (pid, require_skill(skill_id, f"{pname} skills"), level),
                )

    # --- Decoration ---
    for acc in accessories:
        name = ja(acc["names"], f"Accessory {acc['game_id']}")
        db.execute(
            f"INSERT INTO Decoration VALUES ({_ph(6 + len(LANGUAGES))})",
            (
                acc["game_id"], *texts(acc["names"], f"Accessory {acc['game_id']}"),
                acc["level"], acc["allowed_on"],
                acc["rarity"], acc["icon_color"], acc["icon_color_id"],
            ),
        )
        for skill_id, level in acc["skills"].items():
            db.execute(
                "INSERT INTO DecorationSkill VALUES (?,?,?)",
                (acc["game_id"], require_skill(skill_id, f"{name} skills"), level),
            )

    # --- FixedCharm(is_random=falseのみ。鑑定護石4系統はcharm-rules側で扱う)---
    # 鑑定護石の名前はOCRアンカー用にRandomCharmへ格納する
    for amulet in amulets:
        aid = amulet["game_id"]
        if amulet.get("is_random"):
            for rank in amulet["ranks"]:
                db.execute(
                    f"INSERT INTO RandomCharm VALUES ({_ph(3 + len(LANGUAGES))})",
                    (aid, rank["level"],
                     *texts(rank["names"], f"RandomCharm {aid} rank{rank['level']}"),
                     rank["rarity"]),
                )
            continue
        for rank in amulet["ranks"]:
            rank_index = rank["level"]
            rname = ja(rank["names"], f"FixedCharm {aid} rank{rank_index}")
            db.execute(
                f"INSERT INTO FixedCharm VALUES ({_ph(3 + len(LANGUAGES))})",
                (aid, rank_index,
                 *texts(rank["names"], f"FixedCharm {aid} rank{rank_index}"),
                 rank["rarity"]),
            )
            skills_map = rank.get("skills") or {}
            if not (1 <= len(skills_map) <= 2):
                raise ValidationError(f"固定護石のスキル数が想定外({len(skills_map)}): {rname}")
            for skill_id, level in skills_map.items():
                db.execute(
                    "INSERT INTO FixedCharmSkill VALUES (?,?,?,?)",
                    (aid, rank_index, require_skill(skill_id, rname), level),
                )

    # --- Weapon ---
    for kind_index, fname in enumerate(WEAPON_FILES):
        for w in load_json(source_dir, f"weapons/{fname}.json"):
            wid = weapon_id(kind_index, w["game_id"])
            wname = ja(w["names"], f"Weapon {fname} {w['game_id']}")
            db.execute(
                f"INSERT INTO Weapon VALUES ({_ph(7 + len(LANGUAGES))})",
                (
                    wid, w["kind"], *texts(w["names"], f"Weapon {fname} {w['game_id']}"),
                    w["rarity"], w["attack_raw"],
                    w["affinity"], json.dumps(w["slots"]), w.get("series_id"),
                ),
            )
            for skill_id, level in (w.get("skills") or {}).items():
                db.execute(
                    "INSERT INTO WeaponSkill VALUES (?,?,?)",
                    (wid, require_skill(skill_id, wname), level),
                )

    # --- 抽選規則(charm-rules.json → CharmSkillGroup / CharmPattern)---
    # スキル名照合はNFKC正規化(出典は半角KO/UP、ゲームデータは全角ＫＯ/ＵＰ)
    charm_rules_version = "none"
    rules_path = source_dir.parent / "charm-rules" / "charm-rules.json"
    if rules_path.exists():
        rules = json.loads(rules_path.read_text(encoding="utf-8"))
        charm_rules_version = rules["version"]
        by_norm = {}
        for s in skills:
            key = unicodedata.normalize("NFKC", ja(s["names"], "Skill"))
            if key in by_norm:
                raise ValidationError(f"スキル名がNFKC正規化で衝突: {key}")
            by_norm[key] = s["game_id"]
        for gid, group_skills in rules["skillGroups"].items():
            for gs in group_skills:
                skill_id = by_norm.get(unicodedata.normalize("NFKC", gs["name"]))
                if skill_id is None:
                    raise ValidationError(
                        f"規則データのスキル名が解決できません: G{gid} {gs['name']}")
                db.execute(
                    "INSERT INTO CharmSkillGroup VALUES (?,?,?)",
                    (int(gid), skill_id, gs["level"]),
                )
        for i, p in enumerate(rules["patterns"], start=1):
            db.execute(
                "INSERT INTO CharmPattern VALUES (?,?,?,?,?)",
                (i, p["rarity"], p["skill1Group"], p["skill2Group"], p["skill3Group"]),
            )
            for combo in p["slotCombos"]:
                db.execute(
                    "INSERT INTO CharmPatternSlotCombo VALUES (?,?,?)",
                    (i, json.dumps(combo["weaponSlots"]), json.dumps(combo["armorSlots"])),
                )
    else:
        print("警告: charm-rules.json が無いため規則テーブルは空(逆引き・入力補助は無効)",
              file=sys.stderr)

    # --- Meta ---
    db.execute(
        "INSERT INTO Meta VALUES (?,?,?,?)",
        (
            SCHEMA_VERSION,
            datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            read_source_commit(source_dir),
            charm_rules_version,
        ),
    )
    db.commit()

    counts = {
        table: db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        for table in (
            "Skill", "SkillRank", "ArmorSeries", "ArmorSeriesBonusRank",
            "ArmorPiece", "ArmorPieceSkill", "Decoration", "DecorationSkill",
            "FixedCharm", "FixedCharmSkill", "RandomCharm", "Weapon", "WeaponSkill",
            "CharmSkillGroup", "CharmPattern", "CharmPatternSlotCombo",
        )
    }

    # 件数検証: 前回生成時から>10%減で失敗(取得ミス検出。仕様3.4 手順2)
    if out_path.exists():
        prev = sqlite3.connect(f"file:{out_path}?mode=ro", uri=True)
        try:
            for table, count in counts.items():
                try:
                    prev_count = prev.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                except sqlite3.OperationalError:
                    continue  # 旧スキーマにテーブルが無い場合は比較しない
                if prev_count > 0 and count < prev_count * 0.9:
                    raise ValidationError(
                        f"{table} の件数が前回比10%超で減少({prev_count}→{count})。取得ミスの可能性"
                    )
        finally:
            prev.close()

    # 検証を全て通過してから書き出す
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(".db.tmp")
    if tmp_path.exists():
        tmp_path.unlink()
    file_db = sqlite3.connect(tmp_path)
    with file_db:
        db.backup(file_db)
    file_db.close()
    tmp_path.replace(out_path)

    return counts


def main():
    parser = argparse.ArgumentParser(description="mhdb-wilds-data JSON → bundled.db 変換")
    root = Path(__file__).resolve().parent.parent.parent
    parser.add_argument("--source", type=Path, default=root / "data" / "source")
    parser.add_argument("--out", type=Path, default=root / "data" / "generated" / "bundled.db")
    args = parser.parse_args()

    try:
        counts = convert(args.source, args.out)
    except ValidationError as e:
        print(f"検証失敗: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"生成完了: {args.out}")
    for table, count in counts.items():
        print(f"  {table}: {count}")


if __name__ == "__main__":
    main()
