import Foundation

/// 鑑定護石の抽選規則(スキルグループ+パターン)の評価。
/// 逆引き(F-2)の実現可能性判定と、護石入力補助(F-3)の候補絞り込みに使う。
/// 全列挙テーブルは同梱しない(仕様4.2改訂 2026-08-22)。
///
/// 前提(検証済み): 同一スキルは1つの護石に重複しない(2026-08-22実機確認)。
public struct CharmRules: Sendable {
    public struct GroupEntry: Hashable, Sendable {
        public let skillId: SkillId
        public let level: Int

        public init(skillId: SkillId, level: Int) {
            self.skillId = skillId
            self.level = level
        }
    }

    public struct SlotCombo: Hashable, Sendable {
        public let weaponSlots: [Int]
        public let armorSlots: [Int]

        public init(weaponSlots: [Int], armorSlots: [Int]) {
            self.weaponSlots = weaponSlots
            self.armorSlots = armorSlots
        }
    }

    public struct Pattern: Sendable {
        public let rarity: Int
        /// スキル1〜3のグループID(nil = そのスキル枠なし)
        public let skillGroups: [Int?]
        public let slotCombos: [SlotCombo]
    }

    public let groups: [Int: [GroupEntry]]
    public let patterns: [Pattern]

    public var isEmpty: Bool { groups.isEmpty || patterns.isEmpty }

    public init(groups: [Int: [GroupEntry]], patterns: [Pattern]) {
        self.groups = groups
        self.patterns = patterns
    }

    // MARK: - 逆引き用: 要求を満たす護石が抽選上あり得るか

    /// 護石への要求。スキルは「このレベル以上」、スロットは「このサイズ以上が個数分」
    public struct Requirement: Hashable, Sendable {
        public let skills: [SkillId: Int]       // 最大3件
        public let weaponSlots: [Int]           // 必要サイズの配列
        public let armorSlots: [Int]

        public init(skills: [SkillId: Int], weaponSlots: [Int] = [], armorSlots: [Int] = []) {
            self.skills = skills
            self.weaponSlots = weaponSlots
            self.armorSlots = armorSlots
        }
    }

    /// 要求を満たす護石が出現し得る最小レア度。あり得なければnil。
    /// 上位互換(要求以上のレベル・スロット)を含めて判定する(仕様3.2)。
    public func minimumRarity(satisfying req: Requirement) -> Int? {
        guard req.skills.count <= 3 else { return nil }
        var best: Int?
        for pattern in patterns {
            guard pattern.slotCombos.contains(where: {
                Self.fits(required: req.weaponSlots, available: $0.weaponSlots)
                    && Self.fits(required: req.armorSlots, available: $0.armorSlots)
            }) else { continue }
            guard canAssign(skills: Array(req.skills), to: pattern) else { continue }
            best = min(best ?? Int.max, pattern.rarity)
        }
        return best
    }

    /// 要求スキルをパターンのスキル枠に(重複なく)割り当てられるか
    private func canAssign(skills: [(key: SkillId, value: Int)], to pattern: Pattern) -> Bool {
        let slots = pattern.skillGroups
        guard skills.count <= slots.compactMap({ $0 }).count else { return false }

        func assign(_ index: Int, _ used: Set<Int>) -> Bool {
            if index == skills.count { return true }
            let (skillId, minLevel) = skills[index]
            for (slotIndex, groupId) in slots.enumerated() {
                guard let groupId, !used.contains(slotIndex),
                      let entries = groups[groupId],
                      entries.contains(where: { $0.skillId == skillId && $0.level >= minLevel })
                else { continue }
                if assign(index + 1, used.union([slotIndex])) { return true }
            }
            return false
        }
        return assign(0, [])
    }

    /// 必要スロット(サイズ以上)が実スロット構成に収まるか(降順ソートして貪欲対応)
    public static func fits(required: [Int], available: [Int]) -> Bool {
        guard required.count <= available.count else { return false }
        let r = required.sorted(by: >)
        let a = available.sorted(by: >)
        return zip(r, a).allSatisfy { $0 <= $1 }
    }

    // MARK: - 入力補助用(F-3): あり得る組み合わせだけに絞る

    /// スキルN枠(0始まり)に出現し得る全(スキル, レベル)。
    /// `previous` に選択済みの(スキル, レベル)を先頭から渡すと階層的に絞り込む。
    public func candidates(forPosition position: Int, previous: [GroupEntry]) -> Set<GroupEntry> {
        var result: Set<GroupEntry> = []
        let chosenSkillIds = Set(previous.map(\.skillId))
        for pattern in patterns {
            guard position < pattern.skillGroups.count,
                  let groupId = pattern.skillGroups[position],
                  let entries = groups[groupId] else { continue }
            // 選択済みスキルがこのパターンの前段枠に順に合致するか
            let matches = previous.enumerated().allSatisfy { index, entry in
                guard let gid = pattern.skillGroups[index], let g = groups[gid] else { return false }
                return g.contains(entry)
            }
            guard matches else { continue }
            // 同一スキルの重複は除外(2026-08-22実機確認)
            result.formUnion(entries.filter { !chosenSkillIds.contains($0.skillId) })
        }
        return result
    }

    /// スキル構成が確定した護石の、あり得る(レア度, スロット構成)の組
    public func slotCandidates(for chosen: [GroupEntry]) -> Set<RaritySlots> {
        var result: Set<RaritySlots> = []
        for pattern in patterns {
            guard matchesExactly(chosen, pattern) else { continue }
            for combo in pattern.slotCombos {
                result.insert(RaritySlots(rarity: pattern.rarity, slots: combo))
            }
        }
        return result
    }

    public struct RaritySlots: Hashable, Sendable {
        public let rarity: Int
        public let slots: SlotCombo

        public init(rarity: Int, slots: SlotCombo) {
            self.rarity = rarity
            self.slots = slots
        }
    }

    /// 護石(スキル構成の完全形)がこのパターンに合致するか。
    /// パターンの枠数と護石のスキル数が一致し、各枠のグループに順に含まれること。
    private func matchesExactly(_ chosen: [GroupEntry], _ pattern: Pattern) -> Bool {
        let slots = pattern.skillGroups.compactMap { $0 }
        guard chosen.count == slots.count else { return false }
        return zip(chosen, slots).allSatisfy { entry, groupId in
            groups[groupId]?.contains(entry) ?? false
        }
    }

    /// 護石(スキル構成+スロット)が抽選上あり得るか(登録データの妥当性検証用)
    public func isPossible(skills: [GroupEntry], weaponSlots: [Int], armorSlots: [Int]) -> Bool {
        slotCandidates(for: skills).contains {
            $0.slots.weaponSlots.sorted() == weaponSlots.sorted()
                && $0.slots.armorSlots.sorted() == armorSlots.sorted()
        }
    }
}
