import Foundation

/// 検索結果の独立検証器。
/// 探索エンジンとは別経路でスキル発動・スロット妥当性をゼロから再計算し、
/// 「既知の正解」としてテストで正しさを固定するために使う(仕様3.4 手順6)。
public struct ResultValidator {
    public enum Violation: Equatable, CustomStringConvertible {
        case missingPiece(ArmorPieceKind)
        case skillNotSatisfied(SkillId, required: Int, actual: Int)
        case decorationTargetMismatch(String)
        case decorationDoesNotFitSlots(String)
        case activeSkillMismatch(SkillId, reported: Int, recomputed: Int)

        public var description: String {
            switch self {
            case .missingPiece(let kind): return "部位が未装着: \(kind.rawValue)"
            case .skillNotSatisfied(let id, let req, let act): return "スキル\(id)が未達: 要求\(req) 実際\(act)"
            case .decorationTargetMismatch(let name): return "装飾品の装着先が不正: \(name)"
            case .decorationDoesNotFitSlots(let name): return "装飾品がスロットに収まらない: \(name)"
            case .activeSkillMismatch(let id, let rep, let rec): return "発動スキル\(id)の集計不一致: 報告\(rep) 再計算\(rec)"
            }
        }
    }

    let master: MasterDatabase

    public init(master: MasterDatabase) {
        self.master = master
    }

    /// 違反の一覧を返す(空 = 正当)
    public func validate(
        _ set: EquipmentSet,
        condition: SearchCondition
    ) -> [Violation] {
        let weapon = set.weapon
        var violations: [Violation] = []

        for kind in ArmorPieceKind.allCases where set.pieces[kind] == nil {
            violations.append(.missingPiece(kind))
        }

        // 装飾品: 装着先とスロット適合を検証
        var weaponSlotPool: [Int] = (weapon?.slots ?? []) + set.charm.weaponSlots
        var armorSlotPool: [Int] = set.pieces.values.flatMap(\.slots) + set.charm.armorSlots
        for entry in set.decorations {
            let isWeaponSlot = entry.owner == .weapon || entry.owner == .charmWeapon
            let expectedTarget: DecorationTarget = isWeaponSlot ? .weapon : .armor
            if entry.decoration.allowedOn != expectedTarget {
                violations.append(.decorationTargetMismatch(entry.decoration.name))
                continue
            }
            var pool = isWeaponSlot ? weaponSlotPool : armorSlotPool
            // 収まる最小のスロットを消費
            if let index = pool
                .enumerated()
                .filter({ $0.element >= entry.decoration.slotSize })
                .min(by: { $0.element < $1.element })?.offset {
                pool.remove(at: index)
                if isWeaponSlot { weaponSlotPool = pool } else { armorSlotPool = pool }
            } else {
                violations.append(.decorationDoesNotFitSlots(entry.decoration.name))
            }
        }

        // 発動スキルをゼロから再計算
        var recomputed: [SkillId: Int] = [:]
        func add(_ skills: [SkillId: Int]) {
            for (skillId, level) in skills { recomputed[skillId, default: 0] += level }
        }
        if let weapon {
            add(weapon.skills.filter { id, _ in
                let kind = master.skills[id]?.kind
                return kind != .set && kind != .group
            })
        }
        for piece in set.pieces.values { add(piece.skills) }
        add(set.charm.skills)
        for entry in set.decorations { add(entry.decoration.skills) }

        // ボーナススキル: 同一ボーナススキルを持つ装着部位数で発動
        var bonusCount: [SkillId: Int] = [:]
        var thresholds: [SkillId: [Int: Int]] = [:]
        for piece in set.pieces.values {
            guard let series = master.armorSeries[piece.seriesId] else { continue }
            for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 }) {
                bonusCount[bonus.skillId, default: 0] += 1
                thresholds[bonus.skillId, default: [:]].merge(bonus.ranksByPieces) { max($0, $1) }
            }
        }
        // 武器付与のシリーズ/グループスキルも部位数として加算(エンジンと同一意味論)
        if let weapon {
            for (skillId, level) in weapon.skills where master.skills[skillId]?.kind == .set || master.skills[skillId]?.kind == .group {
                bonusCount[skillId, default: 0] += level
                for series in master.armorSeries.values {
                    for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 }) where bonus.skillId == skillId {
                        thresholds[skillId, default: [:]].merge(bonus.ranksByPieces) { max($0, $1) }
                    }
                }
            }
        }
        for (skillId, count) in bonusCount {
            let level = thresholds[skillId]!.filter { $0.key <= count }.values.max() ?? 0
            if level > 0 { recomputed[skillId] = level }
        }
        for (skillId, level) in recomputed {
            if let maxLevel = master.skills[skillId]?.maxLevel {
                recomputed[skillId] = min(level, maxLevel)
            }
        }

        for (skillId, required) in condition.requiredSkills {
            let actual = recomputed[skillId] ?? 0
            if actual < required {
                violations.append(.skillNotSatisfied(skillId, required: required, actual: actual))
            }
        }
        for (skillId, reported) in set.activeSkills {
            let value = recomputed[skillId] ?? 0
            if value != reported {
                violations.append(.activeSkillMismatch(skillId, reported: reported, recomputed: value))
            }
        }
        return violations
    }
}
