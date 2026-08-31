import Foundation

/// 装備検索エンジン(F-1)。UI非依存の純粋ロジック。
/// 枝刈り付き深さ優先探索+装飾品貪欲割り当て(仕様3.1)。
public final class SearchEngine {
    let master: MasterDatabase

    public struct Options: Sendable {
        /// 上限件数(仕様Q-3: 仮100件)
        public var maxResults: Int

        public init(maxResults: Int = 100) {
            self.maxResults = maxResults
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
        var infeasibleLeaves = Set<InfeasibleLeafKey>()

        // 打ち切りは協調キャンセルに1本化(時間予算は呼び出し側がタスクキャンセルで課す。2026-08-26)
        func cancelled() -> Bool {
            nodeCount += 1
            if nodeCount % 1024 == 0, Task.isCancelled { return true }
            return false
        }

        // 装飾品割り当て(葉の内部)の中断判定。nodeCountに依らず即時で判定する
        let shouldAbort: () -> Bool = { Task.isCancelled }

        func dfs(_ depth: Int, _ state: inout State) -> Bool {  // 戻り値: 探索継続するか
            if cancelled() {
                truncated = true
                return false
            }
            if depth == prepared.kindOrder.count {
                // 全部位確定 → 護石を試す(葉の内部でも中断を効かせる。2026-08-24)
                for charm in prepared.charmCandidates {
                    if cancelled() {
                        truncated = true
                        return false
                    }
                    guard !upperBoundFails(prepared, state, remainingKinds: [], charm: charm) else { continue }
                    if let set = finishLeaf(
                        prepared, state, charm: charm,
                        infeasibleLeaves: &infeasibleLeaves, shouldAbort: shouldAbort) {
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

        for weapon in prepared.weaponCandidates {
            var state = State(prepared: prepared, weapon: weapon)
            if !dfs(0, &state) { break }
        }
        if prepared.weaponCandidates.isEmpty {
            var state = State(prepared: prepared, weapon: nil)
            _ = dfs(0, &state)
        }

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
        /// 探索する武器候補(固定選択なら1件。未指定なら全武器から優越除去した候補)
        let weaponCandidates: [Weapon]
        let catalog: DecorationAssigner.Catalog
        // 上界計算用の事前集計
        let maxAdd: [ArmorPieceKind: [SkillId: Int]]
        let maxSlotCount: [ArmorPieceKind: Int]
        let bonusAvail: [ArmorPieceKind: Set<SkillId>]
        /// 1部位が条件ボーナススキル群へ同時に寄与できる最大数(結合上界用)。
        /// ボーナス複数指定時「合計で残り部位が足りない」枝を刈る(2026-08-31)
        let maxBonusContrib: [ArmorPieceKind: Int]
        // 結合上界(スキル): スキル別上界は「全スロットを各スキルが独占できる」前提で
        // 条件スキルが多いと甘すぎるため、総不足量を総寄与量で締める(2026-08-31)
        /// 1部位が条件スキル群へ寄与できる合計レベルの最大(必要量クリップ)
        let maxPieceJoint: [ArmorPieceKind: Int]
        /// 装飾品1個が条件スキル群へ寄与できる合計レベルの最大(必要量クリップ)
        let maxDecoJoint: Int
        /// 護石1個が条件スキル群へ直接寄与できる合計レベルの最大(必要量クリップ)
        let charmJointMax: Int
        /// 防具からも防具用装飾品からも供給されない条件スキル(=武器スロット+護石でしか
        /// 埋められない)。武器スロット総量による結合上界で早期に不能を確定する(2026-08-31)
        let weaponOnlySkillIds: [SkillId]
        /// 武器用装飾品1個がweaponOnlySkillIdsへ寄与できる合計レベルの最大
        let maxWeaponDecoJointWeaponOnly: Int
        /// 護石が持ち得る武器スロットの最大個数
        let charmMaxWeaponSlotCount: Int
        let charmMaxSkill: [SkillId: Int]
        let charmMaxSlotCount: Int
        let bestDecoLevel: [SkillId: Int]  // 1スロットあたり最大寄与(ターゲット不問の上界)
        let bonusContrib: [Int32: Set<SkillId>]  // seriesId → 条件中のボーナススキル
        /// 除外装飾品(F-7)。Catalogには適用済み。逆引きのスロット計画(CharmOracle)でも参照する
        let excludedDecorationIds: Set<Int32>
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
            // 固定・除外(仕様3.1 2026-08-24改訂)。固定は除外に優先する。
            // 除外は優越除去の前に適用する(除外品に優越されて消えた候補を復活させるため)
            var all = master.armorPieces.filter { $0.kind == kind }
            if let pinnedId = condition.pinnedPieceIds[kind] {
                all = all.filter { $0.id == pinnedId }
            } else if !condition.excludedPieceIds.isEmpty {
                all = all.filter { !condition.excludedPieceIds.contains($0.id) }
            }
            // 限界突破ON(既定): 候補を限界突破後スロットに差し替えてから優越除去する。
            // 結果セットにも差し替え後の防具が入るため、以降の処理・表示は分岐不要
            if condition.considerLimitBreak {
                all = all.map { $0.applyingLimitBreak() }
            }
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
        } else if let pinnedCharmId = condition.pinnedFixedCharmId {
            // 生産護石の固定: その護石1択(護石なし・鑑定護石も候補にしない)
            charmCandidates = master.fixedCharms.filter { charm in
                if case .fixed(let id, _) = charm.source { return id == pinnedCharmId }
                return false
            }
        } else {
            let fixedCharms = master.fixedCharms.filter { charm in
                guard case .fixed(let id, _) = charm.source else { return true }
                return !condition.excludedFixedCharmIds.contains(id)
            }
            let allCharms = [Charm.none] + fixedCharms + ownedCharms
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

        // 武器候補: 未指定=「何の武器でも良い」(2026-08-24改訂)。全武器から優越除去
        let weaponCandidates: [Weapon]
        if let weapon {
            weaponCandidates = [weapon]
        } else {
            let bonusSkillIdList = bonusNeeds.map(\.skillId)
            weaponCandidates = nonDominated(master.weapons, keyPath: { candidate in
                Dominance(
                    skills: condSkills.map { candidate.skills[$0] ?? 0 }
                        + bonusSkillIdList.map { candidate.skills[$0] ?? 0 },
                    slotSets: [candidate.slots],
                    extra: 0)
            }).sorted {
                contribution($0.skills, additiveNeeds) > contribution($1.skills, additiveNeeds)
            }
        }

        // 除外装飾品(F-7)は劣候補除去(Catalog内)より先に外す
        let usableDecorations = master.decorations.filter {
            !condition.excludedDecorationIds.contains($0.id)
        }
        let catalog = DecorationAssigner.Catalog(
            decorations: usableDecorations, targetSkills: Set(condSkills))

        func jointContribution(_ skills: [SkillId: Int]) -> Int {
            skills.reduce(0) { $0 + min($1.value, additiveNeeds[$1.key] ?? 0) }
        }

        var maxAdd: [ArmorPieceKind: [SkillId: Int]] = [:]
        var maxSlotCount: [ArmorPieceKind: Int] = [:]
        var bonusAvail: [ArmorPieceKind: Set<SkillId>] = [:]
        var maxBonusContrib: [ArmorPieceKind: Int] = [:]
        var maxPieceJoint: [ArmorPieceKind: Int] = [:]
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
            maxBonusContrib[kind] = candidates.map { (bonusContrib[$0.seriesId] ?? []).count }.max() ?? 0
            maxPieceJoint[kind] = candidates.map { jointContribution($0.skills) }.max() ?? 0
        }
        let maxDecoJoint = usableDecorations.map { jointContribution($0.skills) }.max() ?? 0

        var charmMaxSkill: [SkillId: Int] = [:]
        var charmMaxSlotCount = 0
        let charmJointMax: Int
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
            // 護石はスキル最大3つ: 各スキルのグループ上限(必要量クリップ)の上位3件の和
            charmJointMax = condSkills
                .map { min(charmMaxSkill[$0] ?? 0, additiveNeeds[$0]!) }
                .sorted(by: >).prefix(3).reduce(0, +)
        } else {
            for skillId in condSkills {
                charmMaxSkill[skillId] = charmCandidates.map { $0.skills[skillId] ?? 0 }.max() ?? 0
            }
            charmMaxSlotCount = charmCandidates
                .map { $0.weaponSlots.count + $0.armorSlots.count }.max() ?? 0
            charmJointMax = charmCandidates.map { jointContribution($0.skills) }.max() ?? 0
        }

        var bestDecoLevel: [SkillId: Int] = [:]
        var weaponOnlySkillIds: [SkillId] = []
        for skillId in condSkills {
            let slot3a = DecorationAssigner.Slot(owner: .armor(.head), size: 3)
            let slot3w = DecorationAssigner.Slot(owner: .weapon, size: 3)
            let armorDecoBest = catalog.bestLevel(of: skillId, in: slot3a)
            bestDecoLevel[skillId] = max(armorDecoBest, catalog.bestLevel(of: skillId, in: slot3w))
            let armorPieceBest = ArmorPieceKind.allCases.reduce(0) { $0 + (maxAdd[$1]![skillId] ?? 0) }
            if armorDecoBest == 0 && armorPieceBest == 0 {
                weaponOnlySkillIds.append(skillId)
            }
        }
        let maxWeaponDecoJointWeaponOnly = usableDecorations
            .filter { $0.allowedOn == .weapon }
            .map { deco in
                weaponOnlySkillIds.reduce(0) { $0 + min(deco.skills[$1] ?? 0, additiveNeeds[$1]!) }
            }.max() ?? 0
        let charmMaxWeaponSlotCount: Int
        if charmWildcard {
            charmMaxWeaponSlotCount = master.charmRules.patterns
                .flatMap(\.slotCombos).map { $0.weaponSlots.count }.max() ?? 0
        } else {
            charmMaxWeaponSlotCount = charmCandidates.map { $0.weaponSlots.count }.max() ?? 0
        }

        // 候補の少ない部位から探索(枝刈り効率)
        let kindOrder = ArmorPieceKind.allCases.sorted {
            pieceCandidates[$0]!.count < pieceCandidates[$1]!.count
        }

        return Prepared(
            additiveNeeds: additiveNeeds, bonusNeeds: bonusNeeds,
            kindOrder: kindOrder, pieceCandidates: pieceCandidates,
            charmCandidates: charmCandidates, weaponCandidates: weaponCandidates, catalog: catalog,
            maxAdd: maxAdd, maxSlotCount: maxSlotCount, bonusAvail: bonusAvail,
            maxBonusContrib: maxBonusContrib,
            maxPieceJoint: maxPieceJoint, maxDecoJoint: maxDecoJoint, charmJointMax: charmJointMax,
            weaponOnlySkillIds: weaponOnlySkillIds,
            maxWeaponDecoJointWeaponOnly: maxWeaponDecoJointWeaponOnly,
            charmMaxWeaponSlotCount: charmMaxWeaponSlotCount,
            charmMaxSkill: charmMaxSkill, charmMaxSlotCount: charmMaxSlotCount,
            bestDecoLevel: bestDecoLevel, bonusContrib: bonusContrib,
            excludedDecorationIds: condition.excludedDecorationIds)
    }

    // MARK: - 探索状態

    struct State {
        let weapon: Weapon?
        var pieces: [ArmorPiece] = []
        var have: [SkillId: Int] = [:]
        var bonusCount: [SkillId: Int] = [:]
        var emptySlotCount = 0

        init(prepared: Prepared, weapon: Weapon?) {
            self.weapon = weapon
            if let weapon {
                for (skillId, level) in weapon.skills where prepared.additiveNeeds[skillId] != nil {
                    have[skillId, default: 0] += level
                }
                // 武器付与のシリーズ/グループスキルは発動部位数に加算する
                // (TUで追加されたアーティア武器等。levelを部位数分として数える)
                for bonus in prepared.bonusNeeds {
                    if let level = weapon.skills[bonus.skillId] {
                        bonusCount[bonus.skillId, default: 0] += level
                    }
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

        var jointSkillDeficit = 0
        for (skillId, need) in prepared.additiveNeeds {
            var possible = (state.have[skillId] ?? 0) + charmSkill(skillId)
            for kind in remainingKinds {
                possible += prepared.maxAdd[kind]![skillId] ?? 0
            }
            possible += slotPotential * (prepared.bestDecoLevel[skillId] ?? 0)
            if possible < need { return true }
            jointSkillDeficit += max(0, need - (state.have[skillId] ?? 0))
        }
        // 武器スロット限定の結合上界: 防具からも防具用装飾品からも供給されないスキル群は
        // 武器スロットの装飾品+護石でしか埋められない。武器スロットは増えないため
        // 根本で不能を確定できることが多い(2026-08-31)
        if !prepared.weaponOnlySkillIds.isEmpty {
            var weaponOnlyDeficit = 0
            for skillId in prepared.weaponOnlySkillIds {
                weaponOnlyDeficit += max(
                    0,
                    prepared.additiveNeeds[skillId]! - (state.have[skillId] ?? 0) - charmSkill(skillId))
            }
            if weaponOnlyDeficit > 0 {
                let weaponSlotCount = (state.weapon?.slots.count ?? 0)
                    + (charm?.weaponSlots.count ?? prepared.charmMaxWeaponSlotCount)
                if weaponOnlyDeficit > weaponSlotCount * prepared.maxWeaponDecoJointWeaponOnly {
                    return true
                }
            }
        }

        // 結合上界(スキル): スキル別上界はスロットを重複計上するため、総不足量でも締める。
        // 条件スキルが多いほど効く(2026-08-31)
        if jointSkillDeficit > 0 {
            let charmJoint: Int
            if let charm {
                charmJoint = charm.skills.reduce(0) {
                    $0 + min($1.value, prepared.additiveNeeds[$1.key] ?? 0)
                }
            } else {
                charmJoint = prepared.charmJointMax
            }
            var capacity = charmJoint + slotPotential * prepared.maxDecoJoint
            for kind in remainingKinds { capacity += prepared.maxPieceJoint[kind]! }
            if jointSkillDeficit > capacity { return true }
        }
        var jointBonusDeficit = 0
        for bonus in prepared.bonusNeeds {
            var possible = state.bonusCount[bonus.skillId] ?? 0
            for kind in remainingKinds where prepared.bonusAvail[kind]!.contains(bonus.skillId) {
                possible += 1
            }
            if possible < bonus.requiredPieces { return true }
            jointBonusDeficit += max(0, bonus.requiredPieces - (state.bonusCount[bonus.skillId] ?? 0))
        }
        // 結合上界: ボーナス不足部位数の合計が、残り部位の同時寄与の最大合計を超えたら不能
        // (個別には満たせても「合計で部位が足りない」ケースを刈る。2026-08-31)
        if jointBonusDeficit > 0 {
            let capacity = remainingKinds.reduce(0) { $0 + prepared.maxBonusContrib[$1]! }
            if jointBonusDeficit > capacity { return true }
        }
        return false
    }

    // MARK: - 葉の確定(仕様3.1 手順5〜6)

    /// 充足不能と判明した葉のキー。「不足内容×スロット構成」が同じ葉は割り当ても
    /// 必ず失敗するため、2回目以降のバックトラックを丸ごと省く(2026-08-31)
    struct InfeasibleLeafKey: Hashable {
        let deficits: [SkillId: Int]
        let profile: [Int]  // [防具①②③, 武器①②③] のスロット数
    }

    func finishLeaf(
        _ prepared: Prepared, _ state: State, charm: Charm,
        infeasibleLeaves: inout Set<InfeasibleLeafKey>,
        shouldAbort: () -> Bool = { false }
    ) -> EquipmentSet? {
        for bonus in prepared.bonusNeeds {
            guard (state.bonusCount[bonus.skillId] ?? 0) >= bonus.requiredPieces else { return nil }
        }

        var deficits: [SkillId: Int] = [:]
        for (skillId, need) in prepared.additiveNeeds {
            let have = (state.have[skillId] ?? 0) + (charm.skills[skillId] ?? 0)
            if have < need { deficits[skillId] = need - have }
        }

        let slots = collectSlots(prepared, state, charm: charm)
        var profile = [Int](repeating: 0, count: 6)
        for slot in slots { profile[(slot.isWeapon ? 3 : 0) + slot.size - 1] += 1 }
        let key = InfeasibleLeafKey(deficits: deficits, profile: profile)
        if infeasibleLeaves.contains(key) { return nil }

        // aborted(キャンセル)はnil扱い: 次のcancelled()で探索全体が打ち切られる
        switch DecorationAssigner.assign(
            deficits: deficits, slots: slots, catalog: prepared.catalog,
            shouldAbort: shouldAbort) {
        case .assigned(let assignment):
            return buildSet(prepared, state, charm: charm, slots: slots, assignment: assignment)
        case .infeasible:
            if infeasibleLeaves.count < 500_000 { infeasibleLeaves.insert(key) }
            return nil
        case .aborted:
            return nil
        }
    }

    func collectSlots(_ prepared: Prepared, _ state: State, charm: Charm) -> [DecorationAssigner.Slot] {
        var slots: [DecorationAssigner.Slot] = []
        if let weapon = state.weapon {
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
        if let weapon = state.weapon {
            // set/groupスキルは部位数カウント側で扱うため加算集計から除外
            add(weapon.skills.filter { id, _ in
                let kind = master.skills[id]?.kind
                return kind != .set && kind != .group
            })
        }
        for piece in state.pieces {
            // データ上、部位スキルにシリーズ/グループスキルがLv1で含まれるが、
            // 発動は部位数しきい値側で判定するため加算集計から除外(二重計上防止)
            add(piece.skills.filter { id, _ in
                let kind = master.skills[id]?.kind
                return kind != .set && kind != .group
            })
        }
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
        // 武器付与のシリーズ/グループスキル(seriesId=0枠で加算)
        var weaponBonusLevels: [SkillId: Int] = [:]
        if let weapon = state.weapon {
            for (skillId, level) in weapon.skills where master.skills[skillId]?.kind == .set || master.skills[skillId]?.kind == .group {
                allBonusCount[skillId, default: [:]][0, default: 0] += level
                weaponBonusLevels[skillId] = level
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
            weapon: state.weapon,
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
