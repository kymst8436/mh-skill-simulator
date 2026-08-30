import Foundation
import SQLite3

/// bundled.db(読み取り専用マスタ)の読み込み。
/// アプリ起動時に全件をメモリに展開する(合計6千行程度・数百KB)。
/// SQLiteアクセスは素のC APIを使用(ライブラリ選定Q-5はユーザーデータ層で判断)。
public final class MasterDatabase {
    public let language: DataLanguage
    public let skills: [SkillId: Skill]
    public let armorSeries: [Int32: ArmorSeries]
    public let armorPieces: [ArmorPiece]
    public let decorations: [Decoration]
    public let fixedCharms: [Charm]      // 最終ランクのみ(全所持前提。Q-6)
    public let weapons: [Weapon]
    /// 鑑定護石の名前(選択言語)。護石カメラ読み取りのアンカー照合に使う
    public let randomCharmNames: [String]
    public let charmRules: CharmRules
    public let schemaVersion: Int
    public let charmRulesVersion: String
    public let sourceCommit: String

    public enum LoadError: Error {
        case cannotOpen(String)
        case integrityCheckFailed
        case unexpectedSchema(String)
    }

    public init(path: String, language: DataLanguage = .ja) throws {
        self.language = language
        let sfx = language.columnSuffix
        let db = try SQLiteConnection(path: path)

        guard try db.scalarString("PRAGMA integrity_check") == "ok" else {
            throw LoadError.integrityCheckFailed
        }

        var meta: (Int, String, String) = (0, "", "")
        try db.query("SELECT schemaVersion, charmRulesVersion, sourceCommit FROM Meta") { row in
            meta = (Int(row.int(0)), row.string(1), row.string(2))
        }
        guard meta.0 == 2 else {
            throw LoadError.unexpectedSchema("schemaVersion=\(meta.0)")
        }
        schemaVersion = meta.0
        charmRulesVersion = meta.1
        sourceCommit = meta.2

        var levelEffects: [SkillId: [Int: String]] = [:]
        try db.query("SELECT skillId, level, effect\(sfx) FROM SkillRank") { row in
            levelEffects[SkillId(row.int(0)), default: [:]][Int(row.int(1))] = row.string(2)
        }
        var skills: [SkillId: Skill] = [:]
        try db.query("SELECT id, name\(sfx), kind, maxLevel, description\(sfx) FROM Skill") { row in
            let kind = SkillKind(rawValue: row.string(2))!
            let id = SkillId(row.int(0))
            let summary = row.string(4)  // NULLは空文字で返るためisEmptyで畳む
            skills[id] = Skill(
                id: id, name: row.string(1), kind: kind, maxLevel: Int(row.int(3)),
                summary: summary.isEmpty ? nil : summary,
                levelEffects: levelEffects[id] ?? [:])
        }
        self.skills = skills

        var bonusRanks: [Int32: [(String, Int, Int)]] = [:]
        try db.query("SELECT seriesId, bonusKind, pieces, skillLevel FROM ArmorSeriesBonusRank") { row in
            bonusRanks[Int32(row.int(0)), default: []].append((row.string(1), Int(row.int(2)), Int(row.int(3))))
        }
        var series: [Int32: ArmorSeries] = [:]
        try db.query("SELECT id, name\(sfx), rarity, setBonusSkillId, groupBonusSkillId FROM ArmorSeries") { row in
            let id = Int32(row.int(0))
            func bonus(_ kind: String, _ skillId: SkillId?) -> ArmorSeriesBonus? {
                guard let skillId else { return nil }
                let ranks = (bonusRanks[id] ?? []).filter { $0.0 == kind }
                return ArmorSeriesBonus(
                    skillId: skillId,
                    ranksByPieces: Dictionary(uniqueKeysWithValues: ranks.map { ($0.1, $0.2) }))
            }
            series[id] = ArmorSeries(
                id: id, name: row.string(1), rarity: Int(row.int(2)),
                setBonus: bonus("set", row.isNull(3) ? nil : SkillId(row.int(3))),
                groupBonus: bonus("group", row.isNull(4) ? nil : SkillId(row.int(4))))
        }
        self.armorSeries = series

        var pieceSkills: [Int64: [SkillId: Int]] = [:]
        try db.query("SELECT armorPieceId, skillId, level FROM ArmorPieceSkill") { row in
            pieceSkills[row.int(0), default: [:]][SkillId(row.int(1))] = Int(row.int(2))
        }
        var pieces: [ArmorPiece] = []
        try db.query("""
            SELECT id, seriesId, kind, name\(sfx), defenseMax,
                   resFire, resWater, resThunder, resIce, resDragon, slots
            FROM ArmorPiece
            """) { row in
            pieces.append(ArmorPiece(
                id: row.int(0),
                seriesId: Int32(row.int(1)),
                kind: ArmorPieceKind(rawValue: row.string(2))!,
                name: row.string(3),
                defenseMax: Int(row.int(4)),
                resistances: (5...9).map { Int(row.int($0)) },
                slots: Self.decodeSlots(row.string(10)),
                skills: pieceSkills[row.int(0)] ?? [:]))
        }
        self.armorPieces = pieces

        var decoSkills: [Int32: [SkillId: Int]] = [:]
        try db.query("SELECT decorationId, skillId, level FROM DecorationSkill") { row in
            decoSkills[Int32(row.int(0)), default: [:]][SkillId(row.int(1))] = Int(row.int(2))
        }
        var decorations: [Decoration] = []
        try db.query("SELECT id, name\(sfx), slotSize, allowedOn FROM Decoration") { row in
            decorations.append(Decoration(
                id: Int32(row.int(0)), name: row.string(1),
                slotSize: Int(row.int(2)),
                allowedOn: DecorationTarget(rawValue: row.string(3))!,
                skills: decoSkills[Int32(row.int(0))] ?? [:]))
        }
        self.decorations = decorations

        // 固定護石: 系統ごとに最終ランクのみ検索対象(仕様Q-6)
        var charmSkills: [String: [SkillId: Int]] = [:]
        try db.query("SELECT fixedCharmId, rankIndex, skillId, level FROM FixedCharmSkill") { row in
            charmSkills["\(row.int(0))/\(row.int(1))", default: [:]][SkillId(row.int(2))] = Int(row.int(3))
        }
        var latestRank: [Int32: (rank: Int, name: String)] = [:]
        try db.query("SELECT id, rankIndex, name\(sfx) FROM FixedCharm") { row in
            let id = Int32(row.int(0))
            let rank = Int(row.int(1))
            if latestRank[id] == nil || latestRank[id]!.rank < rank {
                latestRank[id] = (rank, row.string(2))
            }
        }
        self.fixedCharms = latestRank.map { id, entry in
            Charm(source: .fixed(id, entry.rank), name: entry.name,
                  skills: charmSkills["\(id)/\(entry.rank)"] ?? [:],
                  weaponSlots: [], armorSlots: [])  // 固定護石はスロットなし(仕様4.1)
        }

        var randomCharmNames: [String] = []
        try db.query("SELECT name\(sfx) FROM RandomCharm") { row in
            randomCharmNames.append(row.string(0))
        }
        self.randomCharmNames = randomCharmNames

        var weaponSkills: [Int64: [SkillId: Int]] = [:]
        try db.query("SELECT weaponId, skillId, level FROM WeaponSkill") { row in
            weaponSkills[row.int(0), default: [:]][SkillId(row.int(1))] = Int(row.int(2))
        }
        var weapons: [Weapon] = []
        try db.query("SELECT id, kind, name\(sfx), rarity, slots FROM Weapon") { row in
            weapons.append(Weapon(
                id: row.int(0), kind: row.string(1), name: row.string(2),
                rarity: Int(row.int(3)),
                slots: Self.decodeSlots(row.string(4)),
                skills: weaponSkills[row.int(0)] ?? [:]))
        }
        self.weapons = weapons

        // 抽選規則(仕様4.2改訂 2026-08-22)
        var groups: [Int: [CharmRules.GroupEntry]] = [:]
        try db.query("SELECT groupId, skillId, level FROM CharmSkillGroup") { row in
            groups[Int(row.int(0)), default: []].append(
                CharmRules.GroupEntry(skillId: SkillId(row.int(1)), level: Int(row.int(2))))
        }
        var slotCombos: [Int: [CharmRules.SlotCombo]] = [:]
        try db.query("SELECT patternId, weaponSlots, armorSlots FROM CharmPatternSlotCombo") { row in
            slotCombos[Int(row.int(0)), default: []].append(CharmRules.SlotCombo(
                weaponSlots: Self.decodeSlots(row.string(1)),
                armorSlots: Self.decodeSlots(row.string(2))))
        }
        var patterns: [CharmRules.Pattern] = []
        try db.query("SELECT id, rarity, skill1Group, skill2Group, skill3Group FROM CharmPattern") { row in
            patterns.append(CharmRules.Pattern(
                rarity: Int(row.int(1)),
                skillGroups: [
                    Int(row.int(2)),
                    row.isNull(3) ? nil : Int(row.int(3)),
                    row.isNull(4) ? nil : Int(row.int(4)),
                ],
                slotCombos: slotCombos[Int(row.int(0))] ?? []))
        }
        self.charmRules = CharmRules(groups: groups, patterns: patterns)
    }

    /// "[3,1]" 形式のJSON配列
    static func decodeSlots(_ json: String) -> [Int] {
        (try? JSONDecoder().decode([Int].self, from: Data(json.utf8))) ?? []
    }

    /// 必要分(required)を満たし、指定スロットに収まる装飾品(除外適用後)。
    /// 装備詳細の「いずれか」表示の判定に使う(仕様3.1手順5・画面設計4.5)
    public func decorations(
        satisfying required: [SkillId: Int],
        target: DecorationTarget,
        maxSize: Int,
        excluding excludedIds: Set<Int32> = []
    ) -> [Decoration] {
        guard !required.isEmpty else { return [] }
        return decorations.filter { deco in
            deco.allowedOn == target
                && deco.slotSize <= maxSize
                && !excludedIds.contains(deco.id)
                && required.allSatisfy { (deco.skills[$0.key] ?? 0) >= $0.value }
        }
    }

    /// スキルを持つ防具(シリーズ/グループスキルは付与部位そのもの。スキル詳細=画面設計4.14)
    public func armorPieces(withSkill skillId: SkillId) -> [ArmorPiece] {
        armorPieces.filter { $0.skills[skillId] != nil }
    }

    /// シリーズ/グループスキルの発動条件(部位数→発動レベル)。
    /// 同一スキルの規則は全シリーズで共通(bundled.db実測)のためマージして返す
    public func bonusRanks(forSkill skillId: SkillId) -> [Int: Int] {
        var merged: [Int: Int] = [:]
        for series in armorSeries.values {
            for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 })
            where bonus.skillId == skillId {
                merged.merge(bonus.ranksByPieces) { max($0, $1) }
            }
        }
        return merged
    }
}

// MARK: - SQLite薄ラッパ

final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw MasterDatabase.LoadError.cannotOpen(message)
        }
    }

    deinit { sqlite3_close(handle) }

    struct Row {
        let stmt: OpaquePointer
        func int(_ index: Int32) -> Int64 { sqlite3_column_int64(stmt, index) }
        func string(_ index: Int32) -> String {
            sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
        }
        func isNull(_ index: Int32) -> Bool { sqlite3_column_type(stmt, index) == SQLITE_NULL }
    }

    func query(_ sql: String, _ onRow: (Row) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MasterDatabase.LoadError.unexpectedSchema(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            onRow(Row(stmt: stmt))
        }
    }

    func scalarString(_ sql: String) throws -> String {
        var result = ""
        try query(sql) { result = $0.string(0) }
        return result
    }
}
