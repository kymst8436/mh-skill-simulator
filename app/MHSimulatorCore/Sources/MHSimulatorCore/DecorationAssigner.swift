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
                    let kept = usable.filter { candidate in
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
                    // 寄与合計の大きい順の固定順にする(割り当ての対称性除去は
                    // 同型スロット間で候補indexを共有するため、動的な並べ替えはできない)
                    return kept.sorted {
                        let c0 = $0.skills.reduce(0) { targetSkills.contains($1.key) ? $0 + $1.value : $0 }
                        let c1 = $1.skills.reduce(0) { targetSkills.contains($1.key) ? $0 + $1.value : $0 }
                        return c0 != c1 ? c0 > c1 : $0.id < $1.id
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
        // 同型スロット(武器/防具の別+サイズ)が連続するよう並べる(対称性除去の前提)
        let ordered = slots.sorted {
            $0.size != $1.size ? $0.size > $1.size : ($0.isWeapon && !$1.isWeapon)
        }
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

        // 同型スロット(武器/防具の別+サイズが同じ)への割り当ては並べ替えても等価なため、
        // 候補indexを非減少に制限して重複探索を除去する(minOption。2026-08-31)
        func solve(_ index: Int, _ minOption: Int) -> Bool {
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

            let sameAsNext = index + 1 < ordered.count
                && ordered[index + 1].size == slot.size
                && ordered[index + 1].isWeapon == slot.isWeapon
            // 不足スキルに寄与する装飾品を試す(候補順は同型スロット間で共有される固定順)
            let options = catalog.options(for: slot)
            for optionIndex in minOption..<options.count {
                let deco = options[optionIndex]
                guard deco.skills.contains(where: { remaining[$0.key, default: 0] > 0 }) else { continue }
                // この枠が実際に埋める不足分を記録する(代替可能表示=仕様3.1手順5)
                var consumed: [SkillId: Int] = [:]
                for (skill, level) in deco.skills {
                    let before = remaining[skill, default: 0]
                    if before > 0 { consumed[skill] = min(level, before) }
                    remaining[skill, default: 0] = before - level
                }
                assignment.append(DecorationAssignment(
                    owner: slot.owner, slotSize: slot.size, decoration: deco, required: consumed))
                if solve(index + 1, sameAsNext ? optionIndex : 0) { return true }
                assignment.removeLast()
                for (skill, level) in deco.skills {
                    remaining[skill, default: 0] += level
                }
                if aborted { return false }
            }
            // このスロットを空のまま次へ(小さいスロット専用装飾品のための後退。
            // 同型スロットが続く場合は以降も空に固定して対称性を除去)
            return solve(index + 1, sameAsNext ? options.count : 0)
        }

        if solve(0, 0) { return .assigned(assignment) }
        return aborted ? .aborted : .infeasible
    }

    /// 指定の不足ベクトルから、スロット+装飾品で到達できる「残不足ベクトル」の全集合(0クリップ済み)。
    /// バックトラックではなく到達集合を1スロットずつ畳み込むDPで、どのスロットに何を
    /// 入れたかは残不足に影響しないため、集合サイズは∏(不足+1)で抑えられる。
    /// 状態はSIMD16<UInt8>にパックし、同型スロット(武器/防具の別×サイズ)クラスは
    /// 不動点(新しい状態が増えない)に達した時点で残りを打ち切る(2026-08-31)。
    /// 逆引きは条件全体の必要量からこれをスロット構成ごとに1回計算し、
    /// 各葉(充足状態)へはオフセット付き飽和減算で最小残不足を引く。
    /// スキル17個以上は空を返す(護石で埋まる規模を大きく超え、呼び出し側が安全側にフォールバック)。
    /// truncation: 打ち切りで集合が不完全(残不足を過大評価し得る)な場合にその理由
    enum ReachTruncation {
        case cancelled   // 協調キャンセル(時間予算)
        case stateLimit  // 状態数上限(発散防止)
    }

    static func reachableResiduals(
        start: [Int],
        skillOrder: [SkillId],
        slots: [Slot],
        catalog: Catalog,
        stateLimit: Int = 1_000_000,
        shouldAbort: () -> Bool = { false }
    ) -> (residuals: [SIMD16<UInt8>], truncation: ReachTruncation?) {
        guard skillOrder.count <= 16, skillOrder.count == start.count else { return ([], nil) }
        var truncation: ReachTruncation?
        var startVector = SIMD16<UInt8>()
        for (i, value) in start.enumerated() { startVector[i] = UInt8(min(63, max(0, value))) }
        let zero = SIMD16<UInt8>()

        // スロットは(武器/防具の別×サイズ)クラス内で交換可能なため、クラス単位で畳み込む
        var classCounts: [Int: Int] = [:]
        for slot in slots { classCounts[slot.size + (slot.isWeapon ? 8 : 0), default: 0] += 1 }

        var states: Set<SIMD16<UInt8>> = [startVector]
        outer: for (classKey, slotCount) in classCounts.sorted(by: { $0.key > $1.key }) {
            let slot = Slot(owner: classKey > 8 ? .weapon : .armor(.head), size: classKey & 7)
            var seen = Set<SIMD16<UInt8>>()
            var vectors: [SIMD16<UInt8>] = []
            for deco in catalog.options(for: slot) {
                var vector = SIMD16<UInt8>()
                for (i, skillId) in skillOrder.enumerated() {
                    vector[i] = UInt8(min(63, deco.skills[skillId] ?? 0))
                }
                if vector != zero, seen.insert(vector).inserted { vectors.append(vector) }
            }
            guard !vectors.isEmpty else { continue }
            // 前スロットまでに展開済みの状態は同じ装飾品集合で再展開しても増えないため、
            // 直前スロットで新規に現れた状態(フロンティア)だけを展開する
            var frontier = Array(states)
            for _ in 0..<slotCount {
                if shouldAbort() {
                    truncation = .cancelled
                    break outer
                }
                var added: [SIMD16<UInt8>] = []
                for state in frontier where state != zero {
                    for vector in vectors {
                        let reduced = state &- pointwiseMin(state, vector)
                        if reduced == zero {
                            return ([zero], nil)  // 装飾品だけで全充足可能(確定)
                        }
                        if states.insert(reduced).inserted { added.append(reduced) }
                    }
                }
                if added.isEmpty { break }  // 不動点: 同クラスのスロットを増やしても変化なし
                frontier = added
                if states.count > stateLimit {  // 発散防止(高次元条件の安全弁)
                    truncation = .stateLimit
                    break outer
                }
            }
        }
        return (Array(states), truncation)
    }
}
