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
