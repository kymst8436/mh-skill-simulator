import Foundation

/// 装備検索エンジン(F-1)。UI非依存の純粋ロジック。
/// 枝刈り付き深さ優先探索+装飾品貪欲割り当て(仕様3.1)。
public final class SearchEngine {
    let master: MasterDatabase

    public struct Options {
        /// 上限件数(仕様Q-3: 仮100件)
        public var maxResults: Int
        /// 探索打ち切り時刻(仕様3.1: タイムアウト時は途中結果+フラグ)
        public var deadline: Date?

        public init(maxResults: Int = 100, deadline: Date? = nil) {
            self.maxResults = maxResults
            self.deadline = deadline
        }
    }

    public init(master: MasterDatabase) {
        self.master = master
    }

    // MARK: - 公開API

    public func search(
        condition: SearchCondition,
        weapon: Weapon? = nil,
        ownedCharms: [Charm] = [],
        options: Options = Options()
    ) throws -> SearchResult {
        let prepared = try prepare(condition: condition, weapon: weapon, ownedCharms: ownedCharms)
        guard let prepared else {
            // ボーナススキルの提供元が存在しない等、探索するまでもなく0件(仕様3.1エッジケース)
            return SearchResult(sets: [], truncated: false)
        }

        var sets: [EquipmentSet] = []
        var truncated = false
        var nodeCount = 0

        func timedOut() -> Bool {
            nodeCount += 1
            if nodeCount % 1024 == 0, let deadline = options.deadline, Date() > deadline {
                return true
            }
            return false
        }

        func dfs(_ depth: Int, _ state: inout State) -> Bool {  // 戻り値: 探索継続するか
            if timedOut() {
                truncated = true
                return false
            }
            if depth == prepared.kindOrder.count {
                // 全部位確定 → 護石を試す
                for charm in prepared.charmCandidates {
                    guard !upperBoundFails(prepared, state, remainingKinds: [], charm: charm) else { continue }
                    if let set = finishLeaf(prepared, state, charm: charm) {
                        sets.append(set)
                        if sets.count >= options.maxResults {
                            truncated = true
                            return false
                        }
                    }
                }
                return true
            }
            let kind = prepared.kindOrder[depth]
            let remaining = Array(prepared.kindOrder[(depth + 1)...])
            for piece in prepared.pieceCandidates[kind]! {
                state.push(piece, prepared)
                if !upperBoundFails(prepared, state, remainingKinds: remaining, charm: nil) {
                    if !dfs(depth + 1, &state) {
                        state.pop(piece, prepared)
                        return false
                    }
                }
                state.pop(piece, prepared)
            }
            return true
        }

        var state = State(prepared: prepared)
        _ = dfs(0, &state)

        // 防御力maxの高い順(仕様Q-3)
        sets.sort { $0.totalDefenseMax > $1.totalDefenseMax }
        return SearchResult(sets: sets, truncated: truncated)
    }

    // MARK: - 前処理(仕様3.1 手順1〜3)

    struct BonusNeed {
        let skillId: SkillId
        let requiredPieces: Int
        let thresholds: [Int: Int]  // pieces → level
    }

    struct Prepared {
        let additiveNeeds: [SkillId: Int]
        let bonusNeeds: [BonusNeed]
        let kindOrder: [ArmorPieceKind]
        let pieceCandidates: [ArmorPieceKind: [ArmorPiece]]
        let charmCandidates: [Charm]
        let weapon: Weapon?
        let catalog: DecorationAssigner.Catalog
        // 上界計算用の事前集計
        let maxAdd: [ArmorPieceKind: [SkillId: Int]]
        let maxSlotCount: [ArmorPieceKind: Int]
        let bonusAvail: [ArmorPieceKind: Set<SkillId>]
        let charmMaxSkill: [SkillId: Int]
        let charmMaxSlotCount: Int
        let bestDecoLevel: [SkillId: Int]  // 1スロットあたり最大寄与(ターゲット不問の上界)
        let bonusContrib: [Int32: Set<SkillId>]  // seriesId → 条件中のボーナススキル
    }

    /// 条件検証と候補の枝刈り。ボーナススキルが提供不能ならnil(即0件)。
    func prepare(
        condition: SearchCondition,
        weapon: Weapon?,
        ownedCharms: [Charm],
        charmWildcard: Bool = false
    ) throws -> Prepared? {
        guard !condition.requiredSkills.isEmpty else { throw SearchError.emptyCondition }

        var additiveNeeds: [SkillId: Int] = [:]
        var bonusSkillIds: [SkillId: Int] = [:]
        for (skillId, level) in condition.requiredSkills {
            guard let skill = master.skills[skillId] else { throw SearchError.unknownSkill(skillId) }
            guard level >= 1 && level <= skill.maxLevel else { throw SearchError.levelExceedsMax(skillId) }
            switch skill.kind {
            case .armor, .weapon: additiveNeeds[skillId] = level
            case .set, .group: bonusSkillIds[skillId] = level
            }
        }

        // ボーナススキル(シリーズ/グループ): 同一ボーナススキルを持つ部位数で発動判定。
        // α/β等シリーズ違いの混在でも発動するゲーム仕様に合わせ、スキルID単位で数える
        var bonusNeeds: [BonusNeed] = []
        var bonusContrib: [Int32: Set<SkillId>] = [:]
        for (skillId, level) in bonusSkillIds {
            var thresholds: [Int: Int] = [:]
            for series in master.armorSeries.values {
                for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 }) where bonus.skillId == skillId {
                    bonusContrib[series.id, default: []].insert(skillId)
                    thresholds.merge(bonus.ranksByPieces) { max($0, $1) }
                }
            }
            guard let requiredPieces = thresholds.filter({ $0.value >= level }).keys.min() else {
                return nil  // 到達不能(仕様3.1: 条件が上限超→探索せず0件)
            }
            bonusNeeds.append(BonusNeed(skillId: skillId, requiredPieces: requiredPieces, thresholds: thresholds))
        }

        let condSkills = Array(additiveNeeds.keys)

        // 部位候補: (寄与ボーナススキル集合)でグループ化し、同グループ内で優越除去
        var pieceCandidates: [ArmorPieceKind: [ArmorPiece]] = [:]
        for kind in ArmorPieceKind.allCases {
            let all = master.armorPieces.filter { $0.kind == kind }
            var groups: [Set<SkillId>: [ArmorPiece]] = [:]
            for piece in all {
                groups[bonusContrib[piece.seriesId] ?? [], default: []].append(piece)
            }
            var kept: [ArmorPiece] = []
            for (_, members) in groups {
                kept.append(contentsOf: nonDominated(members, keyPath: { piece in
                    Dominance(
                        skills: condSkills.map { piece.skills[$0] ?? 0 },
                        slotSets: [piece.slots],
                        extra: piece.defenseMax)
                }))
            }
            // 条件寄与の大きい順→防御力順(仕様3.1 手順3)
            kept.sort {
                let c0 = contribution($0.skills, additiveNeeds) * 2 + $0.slots.count
                let c1 = contribution($1.skills, additiveNeeds) * 2 + $1.slots.count
                return c0 != c1 ? c0 > c1 : $0.defenseMax > $1.defenseMax
            }
            pieceCandidates[kind] = kept
        }

        // 護石候補: 護石なし+固定護石(最終ランク全所持)+所持鑑定護石。優越除去
        var charmCandidates: [Charm]
        if charmWildcard {
            charmCandidates = []
        } else {
            let allCharms = [Charm.none] + master.fixedCharms + ownedCharms
            charmCandidates = nonDominated(allCharms, keyPath: { charm in
                Dominance(
                    skills: condSkills.map { charm.skills[$0] ?? 0 },
                    slotSets: [charm.weaponSlots, charm.armorSlots],
                    extra: 0)
            })
            charmCandidates.sort {
                contribution($0.skills, additiveNeeds) > contribution($1.skills, additiveNeeds)
            }
        }

        let catalog = DecorationAssigner.Catalog(
            decorations: master.decorations, targetSkills: Set(condSkills))

        var maxAdd: [ArmorPieceKind: [SkillId: Int]] = [:]
        var maxSlotCount: [ArmorPieceKind: Int] = [:]
        var bonusAvail: [ArmorPieceKind: Set<SkillId>] = [:]
        for kind in ArmorPieceKind.allCases {
            let candidates = pieceCandidates[kind]!
            var add: [SkillId: Int] = [:]
            for skillId in condSkills {
                add[skillId] = candidates.map { $0.skills[skillId] ?? 0 }.max() ?? 0
            }
            maxAdd[kind] = add
            maxSlotCount[kind] = candidates.map { $0.slots.count }.max() ?? 0
            bonusAvail[kind] = candidates.reduce(into: Set()) { acc, piece in
                acc.formUnion(bonusContrib[piece.seriesId] ?? [])
            }
        }

        var charmMaxSkill: [SkillId: Int] = [:]
        var charmMaxSlotCount = 0
        if charmWildcard {
            // 逆引きの緩和探索: 護石を「規則上あり得る最良」とみなす上界
            for skillId in condSkills {
                charmMaxSkill[skillId] = master.charmRules.groups.values
                    .flatMap { $0 }
                    .filter { $0.skillId == skillId }
                    .map(\.level).max() ?? 0
            }
            charmMaxSlotCount = master.charmRules.patterns
                .flatMap(\.slotCombos)
                .map { $0.weaponSlots.count + $0.armorSlots.count }.max() ?? 0
        } else {
            for skillId in condSkills {
                charmMaxSkill[skillId] = charmCandidates.map { $0.skills[skillId] ?? 0 }.max() ?? 0
            }
            charmMaxSlotCount = charmCandidates
                .map { $0.weaponSlots.count + $0.armorSlots.count }.max() ?? 0
        }

        var bestDecoLevel: [SkillId: Int] = [:]
        for skillId in condSkills {
            let slot3a = DecorationAssigner.Slot(owner: .armor(.head), size: 3)
            let slot3w = DecorationAssigner.Slot(owner: .weapon, size: 3)
            bestDecoLevel[skillId] = max(
                catalog.bestLevel(of: skillId, in: slot3a),
                catalog.bestLevel(of: skillId, in: slot3w))
        }

        // 候補の少ない部位から探索(枝刈り効率)
        let kindOrder = ArmorPieceKind.allCases.sorted {
            pieceCandidates[$0]!.count < pieceCandidates[$1]!.count
        }

        return Prepared(
            additiveNeeds: additiveNeeds, bonusNeeds: bonusNeeds,
            kindOrder: kindOrder, pieceCandidates: pieceCandidates,
            charmCandidates: charmCandidates, weapon: weapon, catalog: catalog,
            maxAdd: maxAdd, maxSlotCount: maxSlotCount, bonusAvail: bonusAvail,
            charmMaxSkill: charmMaxSkill, charmMaxSlotCount: charmMaxSlotCount,
            bestDecoLevel: bestDecoLevel, bonusContrib: bonusContrib)
    }

    // MARK: - 探索状態

    struct State {
        var pieces: [ArmorPiece] = []
        var have: [SkillId: Int] = [:]
        var bonusCount: [SkillId: Int] = [:]
        var emptySlotCount = 0

        init(prepared: Prepared) {
            if let weapon = prepared.weapon {
                for (skillId, level) in weapon.skills where prepared.additiveNeeds[skillId] != nil {
                    have[skillId, default: 0] += level
                }
                emptySlotCount = weapon.slots.count
            }
        }

        mutating func push(_ piece: ArmorPiece, _ prepared: Prepared) {
            pieces.append(piece)
            for (skillId, level) in piece.skills where prepared.additiveNeeds[skillId] != nil {
                have[skillId, default: 0] += level
            }
            for skillId in prepared.bonusContrib[piece.seriesId] ?? [] {
                bonusCount[skillId, default: 0] += 1
            }
            emptySlotCount += piece.slots.count
        }

        mutating func pop(_ piece: ArmorPiece, _ prepared: Prepared) {
            pieces.removeLast()
            for (skillId, level) in piece.skills where prepared.additiveNeeds[skillId] != nil {
                have[skillId, default: 0] -= level
            }
            for skillId in prepared.bonusContrib[piece.seriesId] ?? [] {
                bonusCount[skillId, default: 0] -= 1
            }
            emptySlotCount -= piece.slots.count
        }
    }

    // MARK: - 上界チェック(仕様3.1 手順4)

    /// 残り部位の最大寄与+最大スロットでも条件に届かないならtrue(枝を切る)
    func upperBoundFails(
        _ prepared: Prepared, _ state: State,
        remainingKinds: [ArmorPieceKind], charm: Charm?
    ) -> Bool {
        let charmSkill: (SkillId) -> Int
        let charmSlots: Int
        if let charm {
            charmSkill = { charm.skills[$0] ?? 0 }
            charmSlots = charm.weaponSlots.count + charm.armorSlots.count
        } else {
            charmSkill = { prepared.charmMaxSkill[$0] ?? 0 }
            charmSlots = prepared.charmMaxSlotCount
        }
        let slotPotential = state.emptySlotCount
            + remainingKinds.reduce(0) { $0 + prepared.maxSlotCount[$1]! }
            + charmSlots

        for (skillId, need) in prepared.additiveNeeds {
            var possible = (state.have[skillId] ?? 0) + charmSkill(skillId)
            for kind in remainingKinds {
                possible += prepared.maxAdd[kind]![skillId] ?? 0
            }
            possible += slotPotential * (prepared.bestDecoLevel[skillId] ?? 0)
            if possible < need { return true }
        }
        for bonus in prepared.bonusNeeds {
            var possible = state.bonusCount[bonus.skillId] ?? 0
            for kind in remainingKinds where prepared.bonusAvail[kind]!.contains(bonus.skillId) {
                possible += 1
            }
            if possible < bonus.requiredPieces { return true }
        }
        return false
    }

    // MARK: - 葉の確定(仕様3.1 手順5〜6)

    func finishLeaf(_ prepared: Prepared, _ state: State, charm: Charm) -> EquipmentSet? {
        for bonus in prepared.bonusNeeds {
            guard (state.bonusCount[bonus.skillId] ?? 0) >= bonus.requiredPieces else { return nil }
        }

        var deficits: [SkillId: Int] = [:]
        for (skillId, need) in prepared.additiveNeeds {
            let have = (state.have[skillId] ?? 0) + (charm.skills[skillId] ?? 0)
            if have < need { deficits[skillId] = need - have }
        }

        let slots = collectSlots(prepared, state, charm: charm)
        guard let assignment = DecorationAssigner.assign(
            deficits: deficits, slots: slots, catalog: prepared.catalog) else { return nil }

        return buildSet(prepared, state, charm: charm, slots: slots, assignment: assignment)
    }

    func collectSlots(_ prepared: Prepared, _ state: State, charm: Charm) -> [DecorationAssigner.Slot] {
        var slots: [DecorationAssigner.Slot] = []
        if let weapon = prepared.weapon {
            slots += weapon.slots.map { DecorationAssigner.Slot(owner: .weapon, size: $0) }
        }
        for piece in state.pieces {
            slots += piece.slots.map { DecorationAssigner.Slot(owner: .armor(piece.kind), size: $0) }
        }
        slots += charm.weaponSlots.map { DecorationAssigner.Slot(owner: .charmWeapon, size: $0) }
        slots += charm.armorSlots.map { DecorationAssigner.Slot(owner: .charmArmor, size: $0) }
        return slots
    }

    func buildSet(
        _ prepared: Prepared, _ state: State, charm: Charm,
        slots: [DecorationAssigner.Slot], assignment: [DecorationAssignment]
    ) -> EquipmentSet {
        // 発動スキル: 加算スキル(全ソース)+ボーナススキル。maxLevelでクリップ(仕様4.5)
        var active: [SkillId: Int] = [:]
        func add(_ skills: [SkillId: Int]) {
            for (skillId, level) in skills { active[skillId, default: 0] += level }
        }
        if let weapon = prepared.weapon { add(weapon.skills) }
        for piece in state.pieces { add(piece.skills) }
        add(charm.skills)
        for entry in assignment { add(entry.decoration.skills) }

        // ボーナススキル発動(条件外のものも含めて全シリーズ分を数える)
        var allBonusCount: [SkillId: [Int32: Int]] = [:]
        for piece in state.pieces {
            guard let series = master.armorSeries[piece.seriesId] else { continue }
            for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 }) {
                allBonusCount[bonus.skillId, default: [:]][piece.seriesId, default: 0] += 1
            }
        }
        for (skillId, bySeries) in allBonusCount {
            let count = bySeries.values.reduce(0, +)
            var level = 0
            for series in master.armorSeries.values {
                for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 }) where bonus.skillId == skillId {
                    level = max(level, bonus.level(forPieces: count))
                }
            }
            if level > 0 { active[skillId] = level }
        }

        for (skillId, level) in active {
            if let maxLevel = master.skills[skillId]?.maxLevel {
                active[skillId] = min(level, maxLevel)
            }
        }

        // 空きスロット: 割り当て済みを大きいスロット優先で消し込む
        var used: [DecorationAssignment.SlotOwner: [Int]] = [:]
        for entry in assignment { used[entry.owner, default: []].append(entry.slotSize) }
        var emptyWeapon: [Int] = []
        var emptyArmor: [Int] = []
        var remainingBySizeOwner = slots.sorted { $0.size > $1.size }
        for (owner, sizes) in used {
            for size in sizes.sorted(by: >) {
                if let index = remainingBySizeOwner.lastIndex(where: { $0.owner == owner && $0.size >= size }) {
                    remainingBySizeOwner.remove(at: index)
                }
            }
        }
        for slot in remainingBySizeOwner {
            if slot.isWeapon { emptyWeapon.append(slot.size) } else { emptyArmor.append(slot.size) }
        }

        var pieceMap: [ArmorPieceKind: ArmorPiece] = [:]
        for piece in state.pieces { pieceMap[piece.kind] = piece }

        return EquipmentSet(
            pieces: pieceMap,
            charm: charm,
            decorations: assignment,
            activeSkills: active,
            totalDefenseMax: state.pieces.reduce(0) { $0 + $1.defenseMax },
            totalResistances: (0..<5).map { i in state.pieces.reduce(0) { $0 + $1.resistances[i] } },
            emptyWeaponSlots: emptyWeapon.sorted(by: >),
            emptyArmorSlots: emptyArmor.sorted(by: >))
    }

    // MARK: - 優越除去

    struct Dominance {
        let skills: [Int]
        let slotSets: [[Int]]
        let extra: Int
    }

    /// aがbを優越: 全条件スキル≧、全スロット集合≧、extra≧
    private func nonDominated<T>(_ items: [T], keyPath: (T) -> Dominance) -> [T] {
        let keys = items.map(keyPath)
        return items.indices.filter { i in
            !items.indices.contains { j in
                guard i != j else { return false }
                let a = keys[j], b = keys[i]
                let dominates = zip(a.skills, b.skills).allSatisfy { $0 >= $1 }
                    && zip(a.slotSets, b.slotSets).allSatisfy { CharmRules.fits(required: $0.1, available: $0.0) }
                    && a.extra >= b.extra
                guard dominates else { return false }
                let reverse = zip(b.skills, a.skills).allSatisfy { $0 >= $1 }
                    && zip(b.slotSets, a.slotSets).allSatisfy { CharmRules.fits(required: $0.1, available: $0.0) }
                    && b.extra >= a.extra
                return !reverse || j < i  // 完全同値は先勝ち
            }
        }.map { items[$0] }
    }

    private func contribution(_ skills: [SkillId: Int], _ needs: [SkillId: Int]) -> Int {
        needs.reduce(0) { $0 + min($1.value, skills[$1.key] ?? 0) }
    }
}
