import Foundation

/// 鑑定護石の逆引き(F-2)。
/// 検索結果ゼロのとき、護石スロットを万能ワイルドカードとした緩和探索で不足分を逆算し、
/// 抽選規則上あり得る護石の要求条件を「入手しやすさ(レア度昇順)」で提示する(仕様3.2)。
public final class CharmOracle {
    /// 「この護石があれば組める」候補
    public struct CharmSuggestion: Hashable, Sendable {
        public let requirement: CharmRules.Requirement
        /// この要求を満たす護石が出現し得る最小レア度
        public let minimumRarity: Int
    }

    public enum Outcome: Equatable, Sendable {
        /// 護石候補(最大N件。仕様Q-4: 仮10件)
        case charms([CharmSuggestion])
        /// 護石では埋まらない → 外せば組めるスキルの代替提示(仕様3.2 手順5)
        case relaxations([SkillId])
        /// 全スキルを外しても組めない(理論上ほぼ発生しない)
        case none
    }

    public struct Options: Sendable {
        public var maxSuggestions: Int
        /// 緩和探索で訪問する葉の上限(発散防止)
        public var leafBudget: Int
        public var deadline: Date?

        public init(maxSuggestions: Int = 10, leafBudget: Int = 50_000, deadline: Date? = nil) {
            self.maxSuggestions = maxSuggestions
            self.leafBudget = leafBudget
            self.deadline = deadline
        }
    }

    private let engine: SearchEngine
    private var master: MasterDatabase { engine.master }

    public init(engine: SearchEngine) {
        self.engine = engine
    }

    public func reverseLookup(
        condition: SearchCondition,
        weapon: Weapon? = nil,
        ownedCharms: [Charm] = [],
        options: Options = Options()
    ) throws -> Outcome {
        guard !master.charmRules.isEmpty else {
            return try relaxationFallback(condition: condition, weapon: weapon, ownedCharms: ownedCharms)
        }

        let requirements = try collectRequirements(
            condition: condition, weapon: weapon, options: options)

        var suggestions: [CharmSuggestion] = []
        for requirement in requirements {
            if let rarity = master.charmRules.minimumRarity(satisfying: requirement) {
                suggestions.append(CharmSuggestion(requirement: requirement, minimumRarity: rarity))
            }
        }
        guard !suggestions.isEmpty else {
            return try relaxationFallback(condition: condition, weapon: weapon, ownedCharms: ownedCharms)
        }

        // 入手しやすさ(レア度昇順)→要求の緩さ(仕様3.2 手順4)
        suggestions.sort {
            if $0.minimumRarity != $1.minimumRarity { return $0.minimumRarity < $1.minimumRarity }
            return laxness($0.requirement) < laxness($1.requirement)
        }
        return .charms(Array(suggestions.prefix(options.maxSuggestions)))
    }

    private func laxness(_ req: CharmRules.Requirement) -> Int {
        req.skills.values.reduce(0, +) + req.weaponSlots.count + req.armorSlots.count
    }

    // MARK: - 緩和探索(仕様3.2 手順1〜2)

    /// 護石ワイルドカードの深さ優先探索で、到達可能な最良状態から護石要求を逆算する
    private func collectRequirements(
        condition: SearchCondition,
        weapon: Weapon?,
        options: Options
    ) throws -> Set<CharmRules.Requirement> {
        guard let prepared = try engine.prepare(
            condition: condition, weapon: weapon, ownedCharms: [], charmWildcard: true) else {
            return []  // ボーナススキル到達不能: 護石では埋まらない
        }

        var requirements: Set<CharmRules.Requirement> = []
        var leafCount = 0
        var nodeCount = 0

        func timedOut() -> Bool {
            nodeCount += 1
            if nodeCount % 1024 == 0, let deadline = options.deadline, Date() > deadline {
                return true
            }
            return false
        }

        func dfs(_ depth: Int, _ state: inout SearchEngine.State) -> Bool {
            if timedOut() { return false }
            if depth == prepared.kindOrder.count {
                leafCount += 1
                visitLeaf(prepared, state, options: options, into: &requirements)
                return leafCount < options.leafBudget
            }
            let kind = prepared.kindOrder[depth]
            let remaining = Array(prepared.kindOrder[(depth + 1)...])
            for piece in prepared.pieceCandidates[kind]! {
                state.push(piece, prepared)
                if !engine.upperBoundFails(prepared, state, remainingKinds: remaining, charm: nil) {
                    if !dfs(depth + 1, &state) {
                        state.pop(piece, prepared)
                        return false
                    }
                }
                state.pop(piece, prepared)
            }
            return true
        }

        for weapon in prepared.weaponCandidates {
            var state = SearchEngine.State(prepared: prepared, weapon: weapon)
            if !dfs(0, &state) { break }
        }
        if prepared.weaponCandidates.isEmpty {
            var state = SearchEngine.State(prepared: prepared, weapon: nil)
            _ = dfs(0, &state)
        }
        return requirements
    }

    private func visitLeaf(
        _ prepared: SearchEngine.Prepared,
        _ state: SearchEngine.State,
        options: Options,
        into requirements: inout Set<CharmRules.Requirement>
    ) {
        // ボーナススキルは護石で補えない
        for bonus in prepared.bonusNeeds {
            guard (state.bonusCount[bonus.skillId] ?? 0) >= bonus.requiredPieces else { return }
        }

        var deficits: [SkillId: Int] = [:]
        for (skillId, need) in prepared.additiveNeeds {
            let have = state.have[skillId] ?? 0
            if have < need { deficits[skillId] = need - have }
        }
        guard !deficits.isEmpty else { return }  // 護石なしで組める(F-1が検出済みのはず)

        // 防具+武器のスロットで埋められる分を先に消し込み、残りを護石への要求とする
        let slots = engine.collectSlots(prepared, state, charm: .none)
        let residual = DecorationAssigner.minimizeResidual(
            deficits: deficits, slots: slots, catalog: prepared.catalog,
            shouldAbort: {
                guard let deadline = options.deadline else { return false }
                return Date() > deadline
            })
        guard !residual.isEmpty else { return }

        // 要求バリエーション: 各不足スキルを「護石スキルで直接」か「護石スロット+装飾品」で賄う
        let skillIds = Array(residual.keys)
        let variantCount = 1 << skillIds.count
        for mask in 0..<variantCount {
            var directSkills: [SkillId: Int] = [:]
            var weaponSlots: [Int] = []
            var armorSlots: [Int] = []
            var feasible = true
            for (index, skillId) in skillIds.enumerated() {
                let deficit = residual[skillId]!
                if mask & (1 << index) == 0 {
                    directSkills[skillId] = deficit
                } else {
                    guard let plan = slotPlan(for: skillId, deficit: deficit) else {
                        feasible = false
                        break
                    }
                    if plan.isWeapon {
                        weaponSlots.append(contentsOf: plan.sizes)
                    } else {
                        armorSlots.append(contentsOf: plan.sizes)
                    }
                }
            }
            guard feasible, directSkills.count <= 3 else { continue }
            requirements.insert(CharmRules.Requirement(
                skills: directSkills, weaponSlots: weaponSlots, armorSlots: armorSlots))
        }
    }

    /// 不足スキルを装飾品で賄う場合の必要スロット(最小サイズ×個数)
    private func slotPlan(for skillId: SkillId, deficit: Int) -> (isWeapon: Bool, sizes: [Int])? {
        // 最大レベル→最小サイズの装飾品を選ぶ。防具スロットを優先(護石は防具スロ中心のため)
        func best(_ target: DecorationTarget) -> Decoration? {
            master.decorations
                .filter { $0.allowedOn == target && ($0.skills[skillId] ?? 0) > 0 }
                .max {
                    let l0 = $0.skills[skillId]!, l1 = $1.skills[skillId]!
                    return l0 != l1 ? l0 < l1 : $0.slotSize > $1.slotSize
                }
        }
        if let deco = best(.armor) {
            let count = (deficit + deco.skills[skillId]! - 1) / deco.skills[skillId]!
            return (false, Array(repeating: deco.slotSize, count: count))
        }
        if let deco = best(.weapon) {
            let count = (deficit + deco.skills[skillId]! - 1) / deco.skills[skillId]!
            return (true, Array(repeating: deco.slotSize, count: count))
        }
        return nil
    }

    // MARK: - 代替提示(仕様3.2 手順5)

    /// 条件スキルを1つ外した場合に組めるかを試行し「外せば組めるスキル」を返す
    private func relaxationFallback(
        condition: SearchCondition,
        weapon: Weapon?,
        ownedCharms: [Charm]
    ) throws -> Outcome {
        var removable: [SkillId] = []
        guard condition.requiredSkills.count > 1 else {
            return .none
        }
        for skillId in condition.requiredSkills.keys {
            var reduced = condition.requiredSkills
            reduced.removeValue(forKey: skillId)
            let result = try engine.search(
                condition: SearchCondition(requiredSkills: reduced),
                weapon: weapon, ownedCharms: ownedCharms,
                options: SearchEngine.Options(maxResults: 1))
            if !result.sets.isEmpty {
                removable.append(skillId)
            }
        }
        return removable.isEmpty ? .none : .relaxations(removable.sorted())
    }
}
