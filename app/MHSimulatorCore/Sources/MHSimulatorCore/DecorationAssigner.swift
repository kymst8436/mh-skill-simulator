import Foundation

/// 不足スキルを装飾品で埋める割り当て器(仕様3.1 手順5)。
/// スロットサイズ降順に候補を試し、失敗時はバックトラックする。
/// 装飾品は全所持前提・個数無制限(仕様: 所持数管理はMVP外)。
struct DecorationAssigner {
    struct Slot {
        let owner: DecorationAssignment.SlotOwner
        let size: Int
        var isWeapon: Bool {
            owner == .weapon || owner == .charmWeapon
        }
    }

    /// 対象スキルに寄与する装飾品だけを射影した候補(ターゲット別・サイズ昇順に引ける形)
    struct Catalog {
        let armor: [[Decoration]]   // index = slotSize-1。そのサイズ以下で使える非劣候補
        let weapon: [[Decoration]]

        init(decorations: [Decoration], targetSkills: Set<SkillId>) {
            func build(_ target: DecorationTarget) -> [[Decoration]] {
                (1...3).map { size in
                    let usable = decorations.filter {
                        $0.allowedOn == target && $0.slotSize <= size
                            && $0.skills.keys.contains(where: targetSkills.contains)
                    }
                    // 対象スキルへの寄与が同一以下の劣候補を除去
                    return usable.filter { candidate in
                        !usable.contains { other in
                            other.id != candidate.id
                                && targetSkills.allSatisfy {
                                    (other.skills[$0] ?? 0) >= (candidate.skills[$0] ?? 0)
                                }
                                && targetSkills.contains {
                                    (other.skills[$0] ?? 0) > (candidate.skills[$0] ?? 0)
                                }
                        }
                    }
                }
            }
            armor = build(.armor)
            weapon = build(.weapon)
        }

        func options(for slot: Slot) -> [Decoration] {
            (slot.isWeapon ? weapon : armor)[slot.size - 1]
        }

        /// 1スロットあたりの最大寄与(上界計算用)
        func bestLevel(of skill: SkillId, in slot: Slot) -> Int {
            options(for: slot).map { $0.skills[skill] ?? 0 }.max() ?? 0
        }
    }

    /// assign の結果。aborted は shouldAbort による中断(=結果未確定。呼び出し側で打ち切り扱いにする)
    enum Result {
        case assigned([DecorationAssignment])
        case infeasible
        case aborted
    }

    /// 不足分を完全に埋める割り当てを探す。
    /// 充足不能ぎりぎりの条件でバックトラックが爆発しうるため、
    /// 全体容量の上界による枝刈りと shouldAbort(デッドライン)による中断を備える(2026-08-24)
    static func assign(
        deficits: [SkillId: Int],
        slots: [Slot],
        catalog: Catalog,
        shouldAbort: () -> Bool = { false }
    ) -> Result {
        var remaining = deficits.filter { $0.value > 0 }
        if remaining.isEmpty { return .assigned([]) }
        let ordered = slots.sorted { $0.size > $1.size }
        var assignment: [DecorationAssignment] = []
        var nodes = 0
        var aborted = false

        func contribution(_ deco: Decoration) -> Int {
            deco.skills.reduce(0) { $0 + min($1.value, max(0, remaining[$1.key] ?? 0)) }
        }

        // 全体容量の上界: 残りスロットそれぞれの最大寄与の合計。
        // スキル単体の上界では「単体では足りるが全体では足りない」ケースを刈れない
        func jointCapacity(from index: Int) -> Int {
            var bestBySize = [[Int]](repeating: [Int](repeating: -1, count: 4), count: 2)
            var capacity = 0
            for slot in ordered[index...] {
                let target = slot.isWeapon ? 1 : 0
                if bestBySize[target][slot.size] < 0 {
                    bestBySize[target][slot.size] = catalog.options(for: slot)
                        .reduce(0) { max($0, contribution($1)) }
                }
                capacity += bestBySize[target][slot.size]
            }
            return capacity
        }

        func solve(_ index: Int) -> Bool {
            if remaining.values.allSatisfy({ $0 <= 0 }) { return true }
            nodes += 1
            if nodes % 512 == 0, shouldAbort() {
                aborted = true
                return false
            }
            guard index < ordered.count else { return false }
            let slot = ordered[index]

            // 上界1(スキル単体): 残りスロット全部を各スキルの最良装飾品で埋めても届かないなら失敗
            var totalDeficit = 0
            for (skill, deficit) in remaining where deficit > 0 {
                totalDeficit += deficit
                let potential = ordered[index...].reduce(0) { $0 + catalog.bestLevel(of: skill, in: $1) }
                if potential < deficit { return false }
            }
            // 上界2(全体容量): スロット総寄与が総不足を下回るなら失敗
            if jointCapacity(from: index) < totalDeficit { return false }

            // 不足スキルに寄与する装飾品を寄与量降順に試す
            let useful = catalog.options(for: slot)
                .filter { deco in deco.skills.contains { remaining[$0.key, default: 0] > 0 } }
                .sorted { contribution($0) > contribution($1) }
            for deco in useful {
                // この枠が実際に埋める不足分を記録する(代替可能表示=仕様3.1手順5)
                var consumed: [SkillId: Int] = [:]
                for (skill, level) in deco.skills {
                    let before = remaining[skill, default: 0]
                    if before > 0 { consumed[skill] = min(level, before) }
                    remaining[skill, default: 0] = before - level
                }
                assignment.append(DecorationAssignment(
                    owner: slot.owner, slotSize: slot.size, decoration: deco, required: consumed))
                if solve(index + 1) { return true }
                assignment.removeLast()
                for (skill, level) in deco.skills {
                    remaining[skill, default: 0] += level
                }
                if aborted { return false }
            }
            // このスロットを空のまま次へ(小さいスロット専用装飾品のための後退)
            return solve(index + 1)
        }

        if solve(0) { return .assigned(assignment) }
        return aborted ? .aborted : .infeasible
    }

    /// 不足分を最小化する割り当て(逆引きの緩和探索用)。残不足の合計が最小の割り当てを返す。
    static func minimizeResidual(
        deficits: [SkillId: Int],
        slots: [Slot],
        catalog: Catalog,
        shouldAbort: () -> Bool = { false }
    ) -> [SkillId: Int] {
        var remaining = deficits.filter { $0.value > 0 }
        if remaining.isEmpty { return [:] }
        let ordered = slots.sorted { $0.size > $1.size }
        var best = remaining
        var bestSum = remaining.values.reduce(0, +)
        var nodes = 0
        var aborted = false

        func residualSum() -> Int {
            remaining.values.reduce(0) { $0 + max(0, $1) }
        }

        func contribution(_ deco: Decoration) -> Int {
            deco.skills.reduce(0) { $0 + min($1.value, max(0, remaining[$1.key] ?? 0)) }
        }

        func jointCapacity(from index: Int) -> Int {
            var bestBySize = [[Int]](repeating: [Int](repeating: -1, count: 4), count: 2)
            var capacity = 0
            for slot in ordered[index...] {
                let target = slot.isWeapon ? 1 : 0
                if bestBySize[target][slot.size] < 0 {
                    bestBySize[target][slot.size] = catalog.options(for: slot)
                        .reduce(0) { max($0, contribution($1)) }
                }
                capacity += bestBySize[target][slot.size]
            }
            return capacity
        }

        func solve(_ index: Int) {
            if aborted { return }
            nodes += 1
            if nodes % 512 == 0, shouldAbort() {
                aborted = true
                return
            }
            let current = residualSum()
            if current == 0 || index == ordered.count {
                if current < bestSum {
                    bestSum = current
                    best = remaining.mapValues { max(0, $0) }.filter { $0.value > 0 }
                }
                return
            }
            // 上界: 残りスロットで削れる最大量(スキル単体と全体容量の小さい方)を
            // 引いても現ベスト以上なら枝刈り
            var optimistic = 0
            for (skill, deficit) in remaining where deficit > 0 {
                let potential = ordered[index...].reduce(0) { $0 + catalog.bestLevel(of: skill, in: $1) }
                optimistic += min(deficit, potential)
            }
            optimistic = min(optimistic, jointCapacity(from: index))
            if current - optimistic >= bestSum { return }

            let slot = ordered[index]
            let useful = catalog.options(for: slot)
                .filter { deco in deco.skills.contains { remaining[$0.key, default: 0] > 0 } }
            for deco in useful {
                for (skill, level) in deco.skills {
                    remaining[skill, default: 0] -= level
                }
                solve(index + 1)
                for (skill, level) in deco.skills {
                    remaining[skill, default: 0] += level
                }
                if aborted { return }
            }
            solve(index + 1)  // 空のまま
        }

        solve(0)
        return best
    }
}
