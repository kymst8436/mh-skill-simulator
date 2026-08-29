import XCTest
@testable import MHSimulatorCore

/// bundled.db読み込みの検証(件数はtools/convert/test_convert.pyと同じ実測値で固定)
final class MasterDatabaseTests: XCTestCase {
    let master = TestSupport.master

    func testCounts() {
        XCTAssertEqual(master.skills.count, 179)
        XCTAssertEqual(master.armorSeries.count, 194)
        XCTAssertEqual(master.armorPieces.count, 714)
        XCTAssertEqual(master.decorations.count, 361)
        XCTAssertEqual(master.fixedCharms.count, 60)  // 系統ごとに最終ランクのみ
        XCTAssertEqual(master.weapons.count, 1188)
    }

    func testSpotCheckSkill() {
        let skill = TestSupport.skill(named: "龍耐性")
        XCTAssertEqual(skill.kind, .armor)
        XCTAssertGreaterThanOrEqual(skill.maxLevel, 3)
        XCTAssertEqual(skill.summary?.hasPrefix("プレイヤーの龍耐性を上げる。"), true)
        XCTAssertEqual(skill.levelEffects[1], "龍耐性＋６")
    }

    /// 全スキルがLv1〜maxLevelの効果文を持つ(スキル詳細=画面設計4.14の前提)
    func testLevelEffectsCoverAllLevels() {
        for skill in master.skills.values {
            XCTAssertEqual(Set(skill.levelEffects.keys), Set(1...skill.maxLevel), skill.name)
        }
    }

    func testArmorPiecesWithSkill() {
        let armorSkill = TestSupport.skill(named: "龍耐性")
        let pieces = master.armorPieces(withSkill: armorSkill.id)
        XCTAssertFalse(pieces.isEmpty)
        XCTAssertTrue(pieces.allSatisfy { $0.skills[armorSkill.id] != nil })
        // シリーズ/グループスキルも付与部位が引ける(ArmorPieceSkillに直接収録)
        let groupSkill = TestSupport.skill(named: "護竜の守り")
        XCTAssertFalse(master.armorPieces(withSkill: groupSkill.id).isEmpty)
    }

    func testBonusRanks() {
        let setSkill = TestSupport.skill(named: "兇爪竜の力")
        XCTAssertEqual(master.bonusRanks(forSkill: setSkill.id), [2: 1, 4: 2])
        let groupSkill = TestSupport.skill(named: "護竜の守り")
        XCTAssertEqual(master.bonusRanks(forSkill: groupSkill.id), [3: 1])
        // 防具スキルには発動条件がない
        XCTAssertTrue(master.bonusRanks(forSkill: TestSupport.skill(named: "龍耐性").id).isEmpty)
    }

    func testFixedCharmsHaveNoSlots() {
        for charm in master.fixedCharms {
            XCTAssertTrue(charm.weaponSlots.isEmpty && charm.armorSlots.isEmpty, charm.name)
            XCTAssertFalse(charm.skills.isEmpty, charm.name)
            XCTAssertLessThanOrEqual(charm.skills.count, 2, charm.name)
        }
    }

    func testCharmRulesLoaded() {
        let rules = master.charmRules
        XCTAssertEqual(rules.groups.count, 10)
        XCTAssertEqual(rules.groups.values.reduce(0) { $0 + $1.count }, 288)
        XCTAssertEqual(rules.patterns.count, 29)
        XCTAssertFalse(rules.isEmpty)
        // 全パターンがスロット組み合わせを持つ
        for pattern in rules.patterns {
            XCTAssertFalse(pattern.slotCombos.isEmpty)
            XCTAssertTrue((5...8).contains(pattern.rarity))
        }
    }

    func testSlotRanges() {
        for piece in master.armorPieces {
            XCTAssertLessThanOrEqual(piece.slots.count, 3, piece.name)
            for size in piece.slots { XCTAssertTrue((1...3).contains(size), piece.name) }
        }
    }
}
