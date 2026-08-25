import XCTest
@testable import MHSimulatorCore

/// 規則評価(逆引き判定・入力補助)の検証
final class CharmRulesTests: XCTestCase {
    let master = TestSupport.master
    var rules: CharmRules { master.charmRules }

    func testSkill1CandidatesNonEmpty() {
        let candidates = rules.candidates(forPosition: 0, previous: [])
        XCTAssertFalse(candidates.isEmpty)
        // スキル1の候補は全スキル数を超えない
        XCTAssertLessThanOrEqual(Set(candidates.map(\.skillId)).count, master.skills.count)
    }

    func testHierarchicalFilteringExcludesChosenSkill() {
        // スキル1を1つ選ぶと、スキル2候補に同一スキルは出ない(2026-08-22実機確認)
        let first = rules.candidates(forPosition: 0, previous: []).sorted { $0.skillId < $1.skillId }.first!
        let second = rules.candidates(forPosition: 1, previous: [first])
        XCTAssertFalse(second.contains { $0.skillId == first.skillId })
    }

    func testKnownCharmIsPossible() {
        // パターンの各枠から実在の組み合わせを構成すればisPossibleはtrue
        let pattern = rules.patterns.first { $0.skillGroups.compactMap { $0 }.count == 3 }!
        var chosen: [CharmRules.GroupEntry] = []
        var usedSkillIds: Set<SkillId> = []
        for groupId in pattern.skillGroups.compactMap({ $0 }) {
            let entry = rules.groups[groupId]!.first { !usedSkillIds.contains($0.skillId) }!
            chosen.append(entry)
            usedSkillIds.insert(entry.skillId)
        }
        let combo = pattern.slotCombos.first!
        XCTAssertTrue(rules.isPossible(
            skills: chosen, weaponSlots: combo.weaponSlots, armorSlots: combo.armorSlots))
    }

    func testImpossibleSlotComboIsRejected() {
        // 防具スロ3×3の護石は規則上あり得ない(最大でも合計3スロット)
        let entry = rules.candidates(forPosition: 0, previous: []).first!
        XCTAssertFalse(rules.isPossible(skills: [entry], weaponSlots: [], armorSlots: [3, 3, 3]))
        XCTAssertNil(rules.minimumRarity(satisfying: CharmRules.Requirement(
            skills: [:], armorSlots: [3, 3, 3])))
    }

    func testWeaponSlotRequiresRarity8() {
        // 武器スロットはレア度8でのみ出現(凡例・パターン表より)
        let rarity = rules.minimumRarity(satisfying: CharmRules.Requirement(
            skills: [:], weaponSlots: [1]))
        XCTAssertEqual(rarity, 8)
    }

    func testMinimumRarityForKnownSkill() {
        // 攻撃はグループ1(レア5のスキル1枠)から出るので最小レア度5
        let attack = TestSupport.skill(named: "攻撃")
        let rarity = rules.minimumRarity(satisfying: CharmRules.Requirement(
            skills: [attack.id: 1]))
        XCTAssertEqual(rarity, 5)
    }

    func testSlotCandidatesForConfirmedSkills() {
        // スキル構成を確定すると(レア度, スロット)候補が提示される(F-3手順4)
        let first = rules.candidates(forPosition: 0, previous: []).sorted { $0.skillId < $1.skillId }.first!
        let second = rules.candidates(forPosition: 1, previous: [first]).sorted { $0.skillId < $1.skillId }.first
        var chosen = [first]
        if let second { chosen.append(second) }
        if let third = rules.candidates(forPosition: 2, previous: chosen).sorted(by: { $0.skillId < $1.skillId }).first {
            chosen.append(third)
        }
        XCTAssertFalse(rules.slotCandidates(for: chosen).isEmpty)
    }
}
