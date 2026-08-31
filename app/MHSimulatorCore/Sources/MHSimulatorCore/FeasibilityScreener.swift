import Foundation

/// 検索前の実現可能性スクリーニング(検索条件画面の確定不可能警告)。
/// 供給側を楽観上界で見積もっても要求に届かない場合のみ違反を返すため、
/// 「違反あり=どう組んでも100%不可能」が保証される。
/// 違反なしは組める保証ではない(実際の可否判定は検索が担当)。
///
/// 供給上界は固定・除外設定や限界突破OFFを考慮しない(考慮しない=供給を多めに
/// 見積もる=健全側)。計算は全部位・全装飾品・抽選パターンの1走査で数ミリ秒。
public struct FeasibilityScreener {
    public enum Violation: Equatable, Sendable {
        /// シリーズ/グループスキルに必要な部位数(武器付与分を除く)が防具5部位の
        /// 同時寄与上限を超える
        case bonusPieces(required: Int, capacity: Int)
        /// 武器スキル(防具・防具用装飾品から供給されないスキル)の要求合計が、
        /// 武器本体+武器スロット+護石の供給上限を超える
        case weaponSkills(demand: Int, capacity: Int)
        /// 武器側・防具側それぞれの不足レベルを、護石1個では同時に補えない
        /// (護石のスキル枠・スロットは武器側と防具側で奪い合いになるため)
        case charmSplit(weaponNeed: Int, armorNeed: Int)
    }

    private let master: MasterDatabase

    public init(master: MasterDatabase) {
        self.master = master
    }

    public func diagnose(condition: SearchCondition, weapon: Weapon?) -> [Violation] {
        var additive: [SkillId: Int] = [:]
        var bonusLevels: [SkillId: Int] = [:]
        for (skillId, level) in condition.requiredSkills {
            guard let skill = master.skills[skillId], level >= 1 else { continue }
            switch skill.kind {
            case .armor, .weapon: additive[skillId] = min(level, skill.maxLevel)
            case .set, .group: bonusLevels[skillId] = min(level, skill.maxLevel)
            }
        }
        var violations: [Violation] = []

        /// 武器由来の供給(部位数換算・スキルレベル共通)。武器未指定は全武器の最大(楽観)
        func weaponGrant(_ skillId: SkillId) -> Int {
            if let weapon { return weapon.skills[skillId] ?? 0 }
            return master.weapons.reduce(0) { max($0, $1.skills[skillId] ?? 0) }
        }

        // MARK: ボーナス部位収支

        var bonusContrib: [Int32: Set<SkillId>] = [:]  // seriesId → 要求中の寄与ボーナス
        var bonusPieceDemand = 0
        for (skillId, level) in bonusLevels {
            var thresholds: [Int: Int] = [:]
            for series in master.armorSeries.values {
                for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 })
                where bonus.skillId == skillId {
                    bonusContrib[series.id, default: []].insert(skillId)
                    thresholds.merge(bonus.ranksByPieces) { max($0, $1) }
                }
            }
            guard let pieces = thresholds.filter({ $0.value >= level }).keys.min() else { continue }
            bonusPieceDemand += max(0, pieces - weaponGrant(skillId))
        }
        if bonusPieceDemand > 0 {
            // 供給: 各部位1つの防具が要求ボーナスへ同時寄与できる数の最大(通常1、
            // 同一シリーズのset/group両要求なら2)の合計
            var capacity = 0
            for kind in ArmorPieceKind.allCases {
                var best = 0
                for piece in master.armorPieces where piece.kind == kind {
                    best = max(best, (bonusContrib[piece.seriesId] ?? []).count)
                }
                capacity += best
            }
            if bonusPieceDemand > capacity {
                violations.append(.bonusPieces(required: bonusPieceDemand, capacity: capacity))
            }
        }

        guard !additive.isEmpty else { return violations }

        // MARK: 供給源の分類(データ駆動: 防具部位・防具用装飾品のどちらからも
        // 供給されないスキル=武器側。それ以外=防具側)

        var perKindSkillMax: [ArmorPieceKind: [SkillId: Int]] = [:]
        for piece in master.armorPieces {
            for (skillId, level) in piece.skills where additive[skillId] != nil {
                perKindSkillMax[piece.kind, default: [:]][skillId, default: 0] =
                    max(perKindSkillMax[piece.kind]?[skillId] ?? 0, level)
            }
        }
        var armorDecoBest: [SkillId: Int] = [:]
        for deco in master.decorations where deco.allowedOn == .armor {
            for (skillId, level) in deco.skills where additive[skillId] != nil {
                armorDecoBest[skillId] = max(armorDecoBest[skillId] ?? 0, level)
            }
        }
        var weaponSide: [SkillId: Int] = [:]
        var armorSide: [SkillId: Int] = [:]
        for (skillId, need) in additive {
            let fromPieces = ArmorPieceKind.allCases.reduce(0) {
                $0 + (perKindSkillMax[$1]?[skillId] ?? 0)
            }
            if fromPieces == 0 && (armorDecoBest[skillId] ?? 0) == 0 {
                weaponSide[skillId] = need
            } else {
                armorSide[skillId] = need
            }
        }

        // MARK: スロット供給(サイズ別・対象別の最良装飾品の結合寄与)

        /// side: 0=武器側スキル向け, 1=防具側スキル向け(キャッシュキー用)
        var decoJointCache: [Int: Int] = [:]
        func decoJoint(
            _ target: DecorationTarget, _ size: Int, side: Int, _ needs: [SkillId: Int]
        ) -> Int {
            let key = (target == .weapon ? 100 : 0) + side * 10 + size
            if let cached = decoJointCache[key] { return cached }
            let value = master.decorations
                .filter { $0.allowedOn == target && $0.slotSize <= size }
                .map { $0.skills.reduce(0) { $0 + min($1.value, needs[$1.key] ?? 0) } }
                .max() ?? 0
            decoJointCache[key] = value
            return value
        }

        let weaponSlots: [Int]
        if let weapon {
            weaponSlots = weapon.slots
        } else {
            // 楽観: スロット数最大の武器を全サイズ③とみなす
            let maxCount = master.weapons.map { $0.slots.count }.max() ?? 0
            weaponSlots = Array(repeating: 3, count: maxCount)
        }

        // MARK: 武器側の護石依存量 W

        let weaponDemand = weaponSide.values.reduce(0, +)
        var weaponSupply = 0
        if !weaponSide.isEmpty {
            for (skillId, need) in weaponSide { weaponSupply += min(need, weaponGrant(skillId)) }
            weaponSupply += weaponSlots.reduce(0) { $0 + decoJoint(.weapon, $1, side: 0, weaponSide) }
        }
        let weaponNeed = max(0, weaponDemand - weaponSupply)

        // MARK: 防具側の護石依存量 A

        let armorDemand = armorSide.values.reduce(0, +)
        var armorSupply = 0
        if !armorSide.isEmpty {
            // 部位: ボーナスで拘束される部位数ぶんは「ボーナス寄与防具の中での最大」に制限。
            // どの部位を自由枠にするかは寄与差の大きい順に選ぶ(楽観=健全側)
            var jointBonusByKind: [Int] = []
            var gains: [Int] = []
            for kind in ArmorPieceKind.allCases {
                var jointAll = 0
                var jointBonus = 0
                for piece in master.armorPieces where piece.kind == kind {
                    let joint = piece.skills.reduce(0) { $0 + min($1.value, armorSide[$1.key] ?? 0) }
                    jointAll = max(jointAll, joint)
                    if !(bonusContrib[piece.seriesId] ?? []).isEmpty {
                        jointBonus = max(jointBonus, joint)
                    }
                }
                jointBonusByKind.append(jointBonus)
                gains.append(jointAll - jointBonus)
            }
            let freePieces = max(0, ArmorPieceKind.allCases.count - bonusPieceDemand)
            armorSupply += jointBonusByKind.reduce(0, +)
                + gains.sorted(by: >).prefix(freePieces).reduce(0, +)
            // 防具スロット: 各部位の最大スロット数(限界突破込み)×最良防具用装飾品
            let slot3Joint = decoJoint(.armor, 3, side: 1, armorSide)
            for kind in ArmorPieceKind.allCases {
                let maxSlots = master.armorPieces
                    .filter { $0.kind == kind }
                    .map { $0.limitBreakSlots.count }.max() ?? 0
                armorSupply += maxSlots * slot3Joint
            }
            // 武器由来の防具側寄与(通常0だがデータ次第であり得るため健全側に加算)
            for (skillId, need) in armorSide { armorSupply += min(need, weaponGrant(skillId)) }
            armorSupply += weaponSlots.reduce(0) { $0 + decoJoint(.weapon, $1, side: 1, armorSide) }
        }
        let armorNeed = max(0, armorDemand - armorSupply)

        guard weaponNeed > 0 || armorNeed > 0 else { return violations }

        // MARK: 護石1個で(武器側weaponNeed, 防具側armorNeed)を同時に賄えるか
        // (スキル枠は抽選パターンのグループ構成に従い、各枠を武器側/防具側の
        //  どちらに使うかの全割当を試す。スロットはパターンごとの構成から加算)

        let rules = master.charmRules
        guard !rules.isEmpty else { return violations }  // 規則不明時は判定しない(健全側)
        var charmCoverable = false
        var bestWeaponFromCharm = 0  // weaponSkills違反の上限表示用(防具側を無視した最大)
        do {
            var groupBestW: [Int: Int] = [:]
            var groupBestA: [Int: Int] = [:]
            for (groupId, entries) in rules.groups {
                for entry in entries {
                    if let need = weaponSide[entry.skillId] {
                        groupBestW[groupId] = max(groupBestW[groupId] ?? 0, min(entry.level, need))
                    }
                    if let need = armorSide[entry.skillId] {
                        groupBestA[groupId] = max(groupBestA[groupId] ?? 0, min(entry.level, need))
                    }
                }
            }
            for pattern in rules.patterns {
                let groupIds = pattern.skillGroups.compactMap { $0 }
                let bestW = groupIds.map { groupBestW[$0] ?? 0 }
                let bestA = groupIds.map { groupBestA[$0] ?? 0 }
                for combo in pattern.slotCombos {
                    let slotW = combo.weaponSlots.reduce(0) { $0 + decoJoint(.weapon, $1, side: 0, weaponSide) }
                    let slotA = combo.armorSlots.reduce(0) { $0 + decoJoint(.armor, $1, side: 1, armorSide) }
                    for mask in 0..<(1 << groupIds.count) {
                        var w = slotW
                        var a = slotA
                        for index in groupIds.indices {
                            if mask & (1 << index) != 0 { w += bestW[index] } else { a += bestA[index] }
                        }
                        bestWeaponFromCharm = max(bestWeaponFromCharm, w)
                        if w >= weaponNeed && a >= armorNeed {
                            charmCoverable = true
                        }
                    }
                }
            }
        }
        if !charmCoverable {
            if armorNeed == 0 {
                violations.append(.weaponSkills(
                    demand: weaponDemand, capacity: weaponSupply + bestWeaponFromCharm))
            } else {
                violations.append(.charmSplit(weaponNeed: weaponNeed, armorNeed: armorNeed))
            }
        }
        return violations
    }
}
