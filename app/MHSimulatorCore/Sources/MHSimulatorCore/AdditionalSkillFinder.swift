import Foundation

/// 追加スキル検索(F-9)。
/// 検索が成立した条件に対し、条件外の各スキルについて「条件に追加しても解が存在する最大レベル」を判定する(仕様3.5)。
/// 打ち切りは協調キャンセル(Task.isCancelled)のみで、時間予算は呼び出し側がタスクキャンセルで課す。
/// スキル単位のチェックポイント(Outcome)を渡すと未判定分から再開できる。
public final class AdditionalSkillFinder {
    /// 追加可能なスキル1件
    public struct Entry: Hashable, Sendable {
        public let skillId: SkillId
        /// 条件に追加しても解が存在する最大レベル
        public let maxAddableLevel: Int

        public init(skillId: SkillId, maxAddableLevel: Int) {
            self.skillId = skillId
            self.maxAddableLevel = maxAddableLevel
        }
    }

    /// 判定結果。pendingが残っていれば時間切れの途中結果(resumingに渡すと続きから判定できる)
    public struct Outcome: Equatable, Sendable {
        /// 追加可能(最大追加レベル降順→スキル名昇順。仕様Q-16)
        public let entries: [Entry]
        /// 判定済み・追加不可(再開時に再計算しないための記録)
        public let notAddable: [SkillId]
        /// 未判定(判定順=理論上界の昇順を保持。仕様3.5手順3)
        public let pending: [SkillId]

        public var isExhaustive: Bool { pending.isEmpty }
        public var determinedCount: Int { entries.count + notAddable.count }
        public var targetCount: Int { determinedCount + pending.count }

        public init(entries: [Entry], notAddable: [SkillId], pending: [SkillId]) {
            self.entries = entries
            self.notAddable = notAddable
            self.pending = pending
        }
    }

    private let engine: SearchEngine
    private var master: MasterDatabase { engine.master }

    public init(engine: SearchEngine) {
        self.engine = engine
    }

    /// onSkillDetermined: スキル1件確定ごとに(確定済み数, 対象総数)を通知(進捗表示用。任意スレッドから呼ばれる)
    public func find(
        condition: SearchCondition,
        weapon: Weapon? = nil,
        ownedCharms: [Charm] = [],
        resuming previous: Outcome? = nil,
        onSkillDetermined: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> Outcome {
        var entries = previous?.entries ?? []
        var notAddable = previous?.notAddable ?? []

        // 対象スキルと理論上界(仕様3.5手順1〜2)。再開時は未判定分のみ
        let bounds = upperBounds(condition: condition, weapon: weapon, ownedCharms: ownedCharms)
        let targets: [(skillId: SkillId, upperBound: Int)]
        if let previous {
            targets = previous.pending.compactMap { skillId in
                guard let ub = bounds[skillId], ub > 0 else { return nil }
                return (skillId, ub)
            }
        } else {
            targets = bounds
                .filter { $0.value > 0 }
                .map { ($0.key, $0.value) }
                .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }  // 上界昇順→ID順(決定的)
        }
        let total = entries.count + notAddable.count + targets.count

        var determinedTargets = 0
        for target in targets {
            if Task.isCancelled { break }
            guard let maxLevel = try probeMaxLevel(
                condition: condition, skillId: target.skillId, upperBound: target.upperBound,
                weapon: weapon, ownedCharms: ownedCharms) else {
                break  // 判定途中でキャンセル: このスキルは未判定のまま(仕様3.5手順5)
            }
            determinedTargets += 1
            if maxLevel > 0 {
                entries.append(Entry(skillId: target.skillId, maxAddableLevel: maxLevel))
            } else {
                notAddable.append(target.skillId)
            }
            onSkillDetermined?(entries.count + notAddable.count, total)
        }

        // 提示順: 最大追加レベル降順→スキル名昇順(仕様Q-16)
        entries.sort {
            if $0.maxAddableLevel != $1.maxAddableLevel {
                return $0.maxAddableLevel > $1.maxAddableLevel
            }
            let name0 = master.skills[$0.skillId]?.name ?? ""
            let name1 = master.skills[$1.skillId]?.name ?? ""
            return name0 != name1 ? name0 < name1 : $0.skillId < $1.skillId
        }
        return Outcome(
            entries: entries, notAddable: notAddable,
            pending: targets[determinedTargets...].map(\.skillId))
    }

    /// 最大追加レベルを判定する(0=追加不可、nil=キャンセルで確定できず)。
    /// まず理論上界レベルで成立を試し、成立すれば1回の探索で確定する(最頻ケース。仕様3.5手順4)。
    /// 不成立ならレベル1から昇順に判定する。成立レベルの単調性(Lv l 成立 → Lv l−1 成立)により
    /// 昇順の打ち切りで正しい最大が求まる
    private func probeMaxLevel(
        condition: SearchCondition, skillId: SkillId, upperBound: Int,
        weapon: Weapon?, ownedCharms: [Charm]
    ) throws -> Int? {
        switch try probe(condition: condition, skillId: skillId, level: upperBound,
                         weapon: weapon, ownedCharms: ownedCharms) {
        case .feasible: return upperBound
        case .cancelled: return nil
        case .infeasible: break
        }
        var best = 0
        for level in 1..<upperBound {
            switch try probe(condition: condition, skillId: skillId, level: level,
                             weapon: weapon, ownedCharms: ownedCharms) {
            case .feasible: best = level
            case .cancelled: return nil
            case .infeasible: return best  // 不成立が確定
            }
        }
        return best
    }

    private enum ProbeResult {
        case feasible
        case infeasible
        /// 0件だがキャンセル起因の可能性があり不成立と確定できない
        case cancelled
    }

    private func probe(
        condition: SearchCondition, skillId: SkillId, level: Int,
        weapon: Weapon?, ownedCharms: [Charm]
    ) throws -> ProbeResult {
        var required = condition.requiredSkills
        required[skillId] = level
        let probeCondition = SearchCondition(
            requiredSkills: required,
            pinnedPieceIds: condition.pinnedPieceIds,
            excludedPieceIds: condition.excludedPieceIds,
            pinnedFixedCharmId: condition.pinnedFixedCharmId,
            excludedFixedCharmIds: condition.excludedFixedCharmIds,
            excludedDecorationIds: condition.excludedDecorationIds,
            considerLimitBreak: condition.considerLimitBreak)

        // 武器未指定時の高速化: 有望武器1本に固定した制限付き探索を先に試す。
        // 武器固定は探索空間の制限なので、成立すれば全体でも成立(健全)。
        // 不成立のときだけ全武器(優越除去が重い)で確かめる
        if weapon == nil, let candidate = heuristicWeapon(for: skillId) {
            let restricted = try engine.search(
                condition: probeCondition, weapon: candidate, ownedCharms: ownedCharms,
                options: SearchEngine.Options(maxResults: 1))
            if !restricted.sets.isEmpty { return .feasible }
            if Task.isCancelled { return .cancelled }
        }

        let result = try engine.search(
            condition: probeCondition, weapon: weapon, ownedCharms: ownedCharms,
            options: SearchEngine.Options(maxResults: 1))
        if !result.sets.isEmpty { return .feasible }
        return Task.isCancelled ? .cancelled : .infeasible
    }

    /// 対象スキルの寄与が最大(同点ならスロット数→スロット合計が最大)の武器
    private func heuristicWeapon(for skillId: SkillId) -> Weapon? {
        master.weapons.max { a, b in
            let levelA = a.skills[skillId] ?? 0, levelB = b.skills[skillId] ?? 0
            if levelA != levelB { return levelA < levelB }
            if a.slots.count != b.slots.count { return a.slots.count < b.slots.count }
            return a.slots.reduce(0, +) < b.slots.reduce(0, +)
        }
    }

    // MARK: - 理論上界の前計算(仕様3.5手順2)

    /// 条件外スキルごとの「これ以上は積めない」レベル。過大評価は許容(探索で正す)が過小評価は不可。
    /// 候補には固定・除外のみ適用し、優越除去は行わない(条件スキル基準の優越で
    /// 条件外スキル持ちの候補が消えると上界を過小評価するため)
    private func upperBounds(
        condition: SearchCondition, weapon: Weapon?, ownedCharms: [Charm]
    ) -> [SkillId: Int] {
        var piecesByKind: [ArmorPieceKind: [ArmorPiece]] = [:]
        for kind in ArmorPieceKind.allCases {
            var all = master.armorPieces.filter { $0.kind == kind }
            if let pinnedId = condition.pinnedPieceIds[kind] {
                all = all.filter { $0.id == pinnedId }
            } else if !condition.excludedPieceIds.isEmpty {
                all = all.filter { !condition.excludedPieceIds.contains($0.id) }
            }
            // 限界突破ONではスロット枠数が増える防具があるため、上界も差し替え後で数える
            if condition.considerLimitBreak {
                all = all.map { $0.applyingLimitBreak() }
            }
            piecesByKind[kind] = all
        }

        let weaponCandidates: [Weapon] = weapon.map { [$0] } ?? master.weapons

        // 護石候補(engine.prepareと同じ固定・除外規則。優越除去なし)
        let charmCandidates: [Charm]
        if let pinnedCharmId = condition.pinnedFixedCharmId {
            charmCandidates = master.fixedCharms.filter { charm in
                if case .fixed(let id, _) = charm.source { return id == pinnedCharmId }
                return false
            }
        } else {
            let fixedCharms = master.fixedCharms.filter { charm in
                guard case .fixed(let id, _) = charm.source else { return true }
                return !condition.excludedFixedCharmIds.contains(id)
            }
            charmCandidates = [Charm.none] + fixedCharms + ownedCharms
        }

        // スロット総数の上界(サイズは問わない)
        let armorSlotCount = ArmorPieceKind.allCases.reduce(0) {
            $0 + (piecesByKind[$1]!.map { $0.slots.count }.max() ?? 0)
        } + (charmCandidates.map { $0.armorSlots.count }.max() ?? 0)
        let weaponSlotCount = (weaponCandidates.map { $0.slots.count }.max() ?? 0)
            + (charmCandidates.map { $0.weaponSlots.count }.max() ?? 0)

        // 装飾品の1スロットあたり最大寄与(スロットサイズ不問の上界)
        var bestArmorDeco: [SkillId: Int] = [:]
        var bestWeaponDeco: [SkillId: Int] = [:]
        for deco in master.decorations where !condition.excludedDecorationIds.contains(deco.id) {
            for (skillId, level) in deco.skills {
                switch deco.allowedOn {
                case .armor: bestArmorDeco[skillId] = max(bestArmorDeco[skillId] ?? 0, level)
                case .weapon: bestWeaponDeco[skillId] = max(bestWeaponDeco[skillId] ?? 0, level)
                }
            }
        }

        var bounds: [SkillId: Int] = [:]
        for skill in master.skills.values where condition.requiredSkills[skill.id] == nil {
            let upperBound: Int
            switch skill.kind {
            case .armor, .weapon:
                var sum = 0
                for kind in ArmorPieceKind.allCases {
                    sum += piecesByKind[kind]!.map { $0.skills[skill.id] ?? 0 }.max() ?? 0
                }
                sum += weaponCandidates.map { $0.skills[skill.id] ?? 0 }.max() ?? 0
                sum += charmCandidates.map { $0.skills[skill.id] ?? 0 }.max() ?? 0
                sum += armorSlotCount * (bestArmorDeco[skill.id] ?? 0)
                sum += weaponSlotCount * (bestWeaponDeco[skill.id] ?? 0)
                upperBound = min(sum, skill.maxLevel)
            case .set, .group:
                // 到達可能な発動部位数(候補に寄与部位が残る部位数+武器付与分。SearchEngine.Stateと同じ扱い)
                var reachablePieces = 0
                for kind in ArmorPieceKind.allCases {
                    let hasContributor = piecesByKind[kind]!.contains { piece in
                        guard let series = master.armorSeries[piece.seriesId] else { return false }
                        return [series.setBonus, series.groupBonus].compactMap { $0 }
                            .contains { $0.skillId == skill.id }
                    }
                    if hasContributor { reachablePieces += 1 }
                }
                reachablePieces += weaponCandidates.map { $0.skills[skill.id] ?? 0 }.max() ?? 0
                var maxLevel = 0
                for series in master.armorSeries.values {
                    for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 })
                    where bonus.skillId == skill.id {
                        maxLevel = max(maxLevel, bonus.level(forPieces: reachablePieces))
                    }
                }
                upperBound = min(maxLevel, skill.maxLevel)
            }
            bounds[skill.id] = upperBound
        }
        return bounds
    }
}
