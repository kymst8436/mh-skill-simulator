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

    public struct Outcome: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// 護石候補(最大N件。仕様Q-4: 仮10件)
            case charms([CharmSuggestion])
            /// 護石では埋まらない → 外せば組めるスキルの代替提示(仕様3.2 手順5)
            case relaxations([SkillId])
            /// 全スキルを外しても組めない(理論上ほぼ発生しない)
            case none
        }

        public let kind: Kind
        /// false = キャンセル(時間予算超過)や葉予算で探索を打ち切った途中結果。
        /// 「真のゼロ件」と「時間内に見つからなかった」をUIで区別するために持つ(2026-08-26)
        public let isExhaustive: Bool

        public init(kind: Kind, isExhaustive: Bool) {
            self.kind = kind
            self.isExhaustive = isExhaustive
        }
    }

    public struct Options: Sendable {
        public var maxSuggestions: Int
        /// 緩和探索で評価する状態(=寄与が異なる組合せの代表)の上限(発散防止)。
        /// 状態DP化(2026-08-31)により通常は数百〜数千で収まり、上限到達は異常系のみ
        public var leafBudget: Int

        public init(maxSuggestions: Int = 10, leafBudget: Int = 50_000) {
            self.maxSuggestions = maxSuggestions
            self.leafBudget = leafBudget
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

        let (requirements, exhaustive) = try collectRequirements(
            condition: condition, weapon: weapon, options: options)

        var suggestions: [CharmSuggestion] = []
        for requirement in requirements {
            if let rarity = master.charmRules.minimumRarity(satisfying: requirement) {
                suggestions.append(CharmSuggestion(requirement: requirement, minimumRarity: rarity))
            }
        }
        guard !suggestions.isEmpty else {
            // 候補ゼロが打ち切りによるものなら、fallbackの結果も網羅とは言えない
            let fallback = try relaxationFallback(
                condition: condition, weapon: weapon, ownedCharms: ownedCharms)
            return Outcome(kind: fallback.kind, isExhaustive: fallback.isExhaustive && exhaustive)
        }

        // 入手しやすさ(レア度昇順)→要求の緩さ(仕様3.2 手順4)
        suggestions.sort {
            if $0.minimumRarity != $1.minimumRarity { return $0.minimumRarity < $1.minimumRarity }
            return laxness($0.requirement) < laxness($1.requirement)
        }
        return Outcome(
            kind: .charms(Array(suggestions.prefix(options.maxSuggestions))),
            isExhaustive: exhaustive)
    }

    private func laxness(_ req: CharmRules.Requirement) -> Int {
        req.skills.values.reduce(0, +) + req.weaponSlots.count + req.armorSlots.count
    }

    // MARK: - 緩和探索(仕様3.2 手順1〜2)

    /// 状態DP用の集約キー。部位の組合せそのものではなく「条件への寄与」だけを持つ。
    /// 同じ寄与の組合せは護石要求も同じになるため、1回だけ評価すれば足りる
    /// (葉の全列挙は組合せ数〜10^6で時間予算内に終わらないため廃止。2026-08-31)
    private struct SkillKey: Hashable {
        let have: [Int]   // 条件スキルの充足量(必要量でクリップ)
        let bonus: [Int]  // ボーナススキルの発動部位数(必要部位数でクリップ)
    }

    private struct Plan {
        let isWeapon: Bool
        let sizes: [Int]
    }

    private struct PlanKey: Hashable {
        let skillId: SkillId
        let deficit: Int
    }

    /// 護石ワイルドカードの緩和探索で、到達可能な最良状態から護石要求を逆算する。
    /// 部位ごとに(充足量・ボーナス部位数・スロット構成)へ集約するDPで、
    /// 同一寄与の組合せを1状態に潰し、スロット構成は優越除去する。
    /// 戻り値のexhaustive: キャンセル・葉予算による打ち切りなしに全探索できたか
    private func collectRequirements(
        condition: SearchCondition,
        weapon: Weapon?,
        options: Options
    ) throws -> (requirements: Set<CharmRules.Requirement>, exhaustive: Bool) {
        guard let prepared = try engine.prepare(
            condition: condition, weapon: weapon, ownedCharms: [], charmWildcard: true) else {
            return ([], true)  // ボーナススキル到達不能: 護石では埋まらない(探索不要の確定)
        }

        let skillOrder = Array(prepared.additiveNeeds.keys).sorted()
        let needs = skillOrder.map { prepared.additiveNeeds[$0]! }
        let bonusRequired = prepared.bonusNeeds.map(\.requiredPieces)
        var bonusIndex: [SkillId: Int] = [:]
        for (index, bonus) in prepared.bonusNeeds.enumerated() { bonusIndex[bonus.skillId] = index }

        // 深さd以降(未確定部位)の上界の事前集計(upperBoundFailsのDP版)
        let depthCount = prepared.kindOrder.count
        var suffixMaxAdd = [[Int]](
            repeating: [Int](repeating: 0, count: skillOrder.count), count: depthCount + 1)
        var suffixSlotMax = [Int](repeating: 0, count: depthCount + 1)
        var suffixBonusAvail = [[Int]](
            repeating: [Int](repeating: 0, count: bonusRequired.count), count: depthCount + 1)
        for depth in stride(from: depthCount - 1, through: 0, by: -1) {
            let kind = prepared.kindOrder[depth]
            for (i, skillId) in skillOrder.enumerated() {
                suffixMaxAdd[depth][i] = suffixMaxAdd[depth + 1][i] + (prepared.maxAdd[kind]![skillId] ?? 0)
            }
            suffixSlotMax[depth] = suffixSlotMax[depth + 1] + prepared.maxSlotCount[kind]!
            for (b, bonus) in prepared.bonusNeeds.enumerated() {
                suffixBonusAvail[depth][b] = suffixBonusAvail[depth + 1][b]
                    + (prepared.bonusAvail[kind]!.contains(bonus.skillId) ? 1 : 0)
            }
        }

        var requirements: Set<CharmRules.Requirement> = []
        var leafCount = 0
        var nodeCount = 0
        var aborted = false
        var planCache: [PlanKey: Plan?] = [:]
        /// スロット構成([防具c1,c2,c3, 武器c1,c2,c3])→ 必要量スタートの到達可能残不足集合
        var reachCache: [[Int]: [SIMD16<UInt8>]] = [:]
        // 抽選規則上あり得ない要求を変種生成の段階で弾くための上限
        let slotCombos = master.charmRules.patterns.flatMap(\.slotCombos)
        let maxCharmWeaponSlots = slotCombos.map { $0.weaponSlots.count }.max() ?? 0
        let maxCharmArmorSlots = slotCombos.map { $0.armorSlots.count }.max() ?? 0

        // 打ち切りは協調キャンセルに1本化(時間予算は呼び出し側がタスクキャンセルで課す。2026-08-26)
        func cancelled() -> Bool {
            nodeCount += 1
            if nodeCount % 1024 == 0, Task.isCancelled { return true }
            return false
        }

        /// 残り部位の最大寄与+最良護石+全スロット装飾品でも届かないなら棄却
        func upperBoundHolds(
            _ have: [Int], _ bonus: [Int], _ armorSlotCount: Int,
            _ depth: Int, _ weaponSlotCount: Int
        ) -> Bool {
            let slotPotential = weaponSlotCount + armorSlotCount
                + suffixSlotMax[depth] + prepared.charmMaxSlotCount
            for i in skillOrder.indices {
                var possible = have[i] + (prepared.charmMaxSkill[skillOrder[i]] ?? 0)
                    + suffixMaxAdd[depth][i]
                possible += slotPotential * (prepared.bestDecoLevel[skillOrder[i]] ?? 0)
                if possible < needs[i] { return false }
            }
            for b in bonusRequired.indices {
                if bonus[b] + suffixBonusAvail[depth][b] < bonusRequired[b] { return false }
            }
            return true
        }

        /// スロット構成(c1,c2,c3)の優越: aで足りる要求はbでも足りる(サイズ上位互換込み)
        func slotsDominate(_ b: [Int], _ a: [Int]) -> Bool {
            b[2] >= a[2] && b[2] + b[1] >= a[2] + a[1]
                && b[2] + b[1] + b[0] >= a[2] + a[1] + a[0]
        }

        func insertSlots(_ kept: inout [[Int]], _ candidate: [Int]) {
            for existing in kept where slotsDominate(existing, candidate) { return }
            kept.removeAll { slotsDominate(candidate, $0) }
            kept.append(candidate)
        }

        /// 1状態(=同一寄与の組合せ全体の代表)から護石要求を生成する
        func evaluateLeaf(_ deficits: [SkillId: Int], _ weapon: Weapon?, _ slotCounts: [Int]) {
            // 防具+武器のスロットで埋められる分を先に消し込み、残りを護石への要求とする。
            // 到達可能な残不足集合は「条件の必要量スタート」でスロット構成ごとに1回だけ計算し、
            // 各葉へは充足済み分(needs-deficits)のオフセット付き飽和減算で最小残不足を引く
            let weaponSlots = (weapon?.slots ?? []).sorted()
            var weaponClassCounts = [0, 0, 0]
            for size in weaponSlots { weaponClassCounts[size - 1] += 1 }
            let profileKey = slotCounts + weaponClassCounts
            let reach: [SIMD16<UInt8>]
            if let cached = reachCache[profileKey] {
                reach = cached
            } else {
                var slots = weaponSlots.map { DecorationAssigner.Slot(owner: .weapon, size: $0) }
                for size in 1...3 {
                    // 部位はどれでも等価(割り当ては武器/防具の別しか見ない)ため代表としてheadを使う
                    slots += Array(
                        repeating: DecorationAssigner.Slot(owner: .armor(.head), size: size),
                        count: slotCounts[size - 1])
                }
                reach = DecorationAssigner.reachableResiduals(
                    start: needs, skillOrder: skillOrder, slots: slots,
                    catalog: prepared.catalog, shouldAbort: { Task.isCancelled })
                reachCache[profileKey] = reach
            }

            let residual: [SkillId: Int]
            if reach.isEmpty {
                // 17スキル以上のフォールバック: 縮約せずそのまま要求へ(後段の規則判定で必ず棄却される)
                residual = deficits
            } else {
                // オフセット = 充足済み量(needs - deficits)。到達残不足からこの分を差し引ける
                var offset = SIMD16<UInt8>()
                for (i, skillId) in skillOrder.enumerated() {
                    offset[i] = UInt8(min(63, needs[i] - (deficits[skillId] ?? 0)))
                }
                var best = SIMD16<UInt8>(repeating: 63)
                var bestSum = Int.max
                for reached in reach {
                    let candidate = reached &- pointwiseMin(reached, offset)
                    var sum = 0
                    for i in skillOrder.indices { sum += Int(candidate[i]) }
                    if sum > bestSum { continue }
                    if sum == bestSum {
                        // 同点は辞書順(集合の列挙順に依らず決定的にする)
                        var precedes = false
                        for i in skillOrder.indices where candidate[i] != best[i] {
                            precedes = candidate[i] < best[i]
                            break
                        }
                        guard precedes else { continue }
                    }
                    best = candidate
                    bestSum = sum
                }
                guard bestSum > 0 else { return }  // 装飾品だけで埋まる(F-1が検出済みのはず)
                var converted: [SkillId: Int] = [:]
                for (i, skillId) in skillOrder.enumerated() where best[i] > 0 {
                    converted[skillId] = Int(best[i])
                }
                residual = converted
            }
            guard !residual.isEmpty else { return }

            // 要求バリエーション: 各不足スキルを「護石スキルで直接」か「護石スロット+装飾品」で賄う
            let skillIds = residual.keys.sorted()
            let variantCount = 1 << skillIds.count
            for mask in 0..<variantCount {
                var directSkills: [SkillId: Int] = [:]
                var weaponSlotReq: [Int] = []
                var armorSlotReq: [Int] = []
                var feasible = true
                for (index, skillId) in skillIds.enumerated() {
                    let deficit = residual[skillId]!
                    if mask & (1 << index) == 0 {
                        // 抽選規則のグループ上限を超えるレベルは直接要求できない
                        guard deficit <= prepared.charmMaxSkill[skillId] ?? 0 else {
                            feasible = false
                            break
                        }
                        directSkills[skillId] = deficit
                    } else {
                        let planKey = PlanKey(skillId: skillId, deficit: deficit)
                        let plan: Plan?
                        if let cached = planCache[planKey] {
                            plan = cached
                        } else {
                            plan = slotPlan(
                                for: skillId, deficit: deficit,
                                excluding: prepared.excludedDecorationIds)
                            planCache[planKey] = plan
                        }
                        guard let plan else {
                            feasible = false
                            break
                        }
                        if plan.isWeapon {
                            weaponSlotReq.append(contentsOf: plan.sizes)
                        } else {
                            armorSlotReq.append(contentsOf: plan.sizes)
                        }
                    }
                }
                guard feasible, directSkills.count <= 3,
                      weaponSlotReq.count <= maxCharmWeaponSlots,
                      armorSlotReq.count <= maxCharmArmorSlots else { continue }
                requirements.insert(CharmRules.Requirement(
                    skills: directSkills, weaponSlots: weaponSlotReq, armorSlots: armorSlotReq))
            }
        }

        /// 武器1候補ぶんのDP。戻り値: 探索継続するか(falseで全体打ち切り)
        func runDP(weapon: Weapon?) -> Bool {
            var initialHave = [Int](repeating: 0, count: skillOrder.count)
            var initialBonus = [Int](repeating: 0, count: bonusRequired.count)
            let weaponSlotCount = weapon?.slots.count ?? 0
            if let weapon {
                for (i, skillId) in skillOrder.enumerated() {
                    initialHave[i] = min(needs[i], weapon.skills[skillId] ?? 0)
                }
                // 武器付与のシリーズ/グループスキル(SearchEngine.State.initと同じ扱い)
                for (b, bonus) in prepared.bonusNeeds.enumerated() {
                    if let level = weapon.skills[bonus.skillId] {
                        initialBonus[b] = min(bonusRequired[b], level)
                    }
                }
            }
            var current: [SkillKey: [[Int]]] = [
                SkillKey(have: initialHave, bonus: initialBonus): [[0, 0, 0]]
            ]
            for depth in 0..<depthCount {
                let pieces = prepared.pieceCandidates[prepared.kindOrder[depth]]!
                var next: [SkillKey: [[Int]]] = [:]
                for (key, slotVariants) in current {
                    for piece in pieces {
                        if cancelled() {
                            aborted = true
                            return false
                        }
                        var have = key.have
                        for (i, skillId) in skillOrder.enumerated() {
                            if let level = piece.skills[skillId] {
                                have[i] = min(needs[i], have[i] + level)
                            }
                        }
                        var bonus = key.bonus
                        for skillId in prepared.bonusContrib[piece.seriesId] ?? [] {
                            if let b = bonusIndex[skillId] {
                                bonus[b] = min(bonusRequired[b], bonus[b] + 1)
                            }
                        }
                        let nextKey = SkillKey(have: have, bonus: bonus)
                        for slots in slotVariants {
                            var newSlots = slots
                            for size in piece.slots { newSlots[size - 1] += 1 }
                            guard upperBoundHolds(
                                have, bonus, newSlots.reduce(0, +), depth + 1, weaponSlotCount)
                            else { continue }
                            insertSlots(&next[nextKey, default: []], newSlots)
                        }
                    }
                }
                current = next
                if Task.isCancelled {
                    aborted = true
                    return false
                }
            }
            // 最終状態を集めて大域優越除去: 充足もスロットも上回る状態があるなら、
            // 劣る側はより強い(または同等の)護石要求しか生まないため評価しない
            struct FinalEntry {
                let have: [Int]
                let slots: [Int]
                let suffix: [Int]  // サイズ上位互換込みのスロット比較用(③, ③+②, 全部)
                let deficitSum: Int
            }
            var entries: [FinalEntry] = []
            for (key, slotVariants) in current {
                guard zip(key.bonus, bonusRequired).allSatisfy({ $0 >= $1 }) else { continue }
                let deficitSum = skillOrder.indices.reduce(0) { $0 + (needs[$1] - key.have[$1]) }
                guard deficitSum > 0 else { continue }  // 護石なしで組める(F-1が検出済みのはず)
                for slots in slotVariants {
                    entries.append(FinalEntry(
                        have: key.have, slots: slots,
                        suffix: [slots[2], slots[2] + slots[1], slots[2] + slots[1] + slots[0]],
                        deficitSum: deficitSum))
                }
            }
            let kept = entries.indices.filter { i in
                !entries.indices.contains { j in
                    guard i != j else { return false }
                    let a = entries[j], b = entries[i]
                    let dominates = zip(a.have, b.have).allSatisfy { $0 >= $1 }
                        && zip(a.suffix, b.suffix).allSatisfy { $0 >= $1 }
                    guard dominates else { return false }
                    let reverse = zip(b.have, a.have).allSatisfy { $0 >= $1 }
                        && zip(b.suffix, a.suffix).allSatisfy { $0 >= $1 }
                    return !reverse || j < i  // 完全同値は先勝ち
                }
            }
            // 不足の小さい順に評価(予算打ち切り時に有望な候補から残るように+決定的な順序)
            let orderedEntries = kept.map { entries[$0] }.sorted {
                if $0.deficitSum != $1.deficitSum { return $0.deficitSum < $1.deficitSum }
                if $0.have != $1.have {
                    return $0.have.lexicographicallyPrecedes($1.have) == false
                }
                return $1.suffix.lexicographicallyPrecedes($0.suffix)
            }
            for entry in orderedEntries {
                if Task.isCancelled {
                    aborted = true
                    return false
                }
                var deficits: [SkillId: Int] = [:]
                for (i, skillId) in skillOrder.enumerated() where entry.have[i] < needs[i] {
                    deficits[skillId] = needs[i] - entry.have[i]
                }
                evaluateLeaf(deficits, weapon, entry.slots)
                leafCount += 1
                if leafCount >= options.leafBudget {
                    aborted = true
                    return false
                }
            }
            return true
        }

        for weapon in prepared.weaponCandidates {
            if !runDP(weapon: weapon) { break }
        }
        if prepared.weaponCandidates.isEmpty {
            _ = runDP(weapon: nil)
        }
        return (requirements, !aborted)
    }

    /// 不足スキルを装飾品で賄う場合の必要スロット(最小サイズ×個数)
    private func slotPlan(
        for skillId: SkillId, deficit: Int, excluding excludedIds: Set<Int32>
    ) -> Plan? {
        // 最大レベル→最小サイズの装飾品を選ぶ。防具スロットを優先(護石は防具スロ中心のため)
        func best(_ target: DecorationTarget) -> Decoration? {
            master.decorations
                .filter {
                    $0.allowedOn == target && ($0.skills[skillId] ?? 0) > 0
                        && !excludedIds.contains($0.id)
                }
                .max {
                    let l0 = $0.skills[skillId]!, l1 = $1.skills[skillId]!
                    return l0 != l1 ? l0 < l1 : $0.slotSize > $1.slotSize
                }
        }
        if let deco = best(.armor) {
            let count = (deficit + deco.skills[skillId]! - 1) / deco.skills[skillId]!
            return Plan(isWeapon: false, sizes: Array(repeating: deco.slotSize, count: count))
        }
        if let deco = best(.weapon) {
            let count = (deficit + deco.skills[skillId]! - 1) / deco.skills[skillId]!
            return Plan(isWeapon: true, sizes: Array(repeating: deco.slotSize, count: count))
        }
        return nil
    }

    // MARK: - 代替提示(仕様3.2 手順5)

    /// 条件スキルを1つ外した場合に組めるかを試行し「外せば組めるスキル」を返す。
    /// engine.searchは協調キャンセルに従うため、呼び出し側の時間予算超過でここも自動的に止まる
    private func relaxationFallback(
        condition: SearchCondition,
        weapon: Weapon?,
        ownedCharms: [Charm]
    ) throws -> Outcome {
        var removable: [SkillId] = []
        var aborted = false
        guard condition.requiredSkills.count > 1 else {
            return Outcome(kind: .none, isExhaustive: true)
        }
        for skillId in condition.requiredSkills.keys {
            if Task.isCancelled {
                aborted = true  // 残りスキルは未試行(時間内に検証しきれなかった)
                break
            }
            var reduced = condition.requiredSkills
            reduced.removeValue(forKey: skillId)
            let result = try engine.search(
                condition: SearchCondition(requiredSkills: reduced),
                weapon: weapon, ownedCharms: ownedCharms,
                options: SearchEngine.Options(maxResults: 1))
            if !result.sets.isEmpty {
                removable.append(skillId)
            } else if Task.isCancelled {
                aborted = true  // 0件はキャンセルによる途中打ち切りの可能性があり確定できない
                break
            }
        }
        let kind: Outcome.Kind = removable.isEmpty ? .none : .relaxations(removable.sorted())
        return Outcome(kind: kind, isExhaustive: !aborted)
    }
}
