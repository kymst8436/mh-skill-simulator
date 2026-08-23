import XCTest
@testable import MHSimulatorCore

/// 逆引き(F-2)の検証。提示候補は全列挙DB(enumerated.db)と突き合わせて実在を確認する
final class CharmOracleTests: XCTestCase {
    let master = TestSupport.master
    lazy var engine = SearchEngine(master: master)
    lazy var oracle = CharmOracle(engine: engine)

    func testSuggestsCharmForWeaponSkill() throws {
        // 攻撃Lv1は武器未選択・護石なしでは組めない(SearchEngineTestsで確認済み)
        // →逆引きは「攻撃を持つ護石」を提示するはず
        let attack = TestSupport.skill(named: "攻撃")
        let condition = SearchCondition(requiredSkills: [attack.id: 1])
        let outcome = try oracle.reverseLookup(condition: condition, weapon: TestSupport.slotlessWeapon)
        guard case .charms(let suggestions) = outcome else {
            return XCTFail("護石候補が提示されるべき: \(outcome)")
        }
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertLessThanOrEqual(suggestions.count, 10)  // 仕様Q-4
        // レア度昇順
        let rarities = suggestions.map(\.minimumRarity)
        XCTAssertEqual(rarities, rarities.sorted())
        // 少なくとも1候補は攻撃スキルを直接要求している
        XCTAssertTrue(suggestions.contains { ($0.requirement.skills[attack.id] ?? 0) >= 1 })
    }

    func testSuggestionsExistInEnumeratedDb() throws {
        // スキルのみ要求の候補は、全列挙DBに上位互換の護石が実在するはず(規則評価の相互検証)
        let attack = TestSupport.skill(named: "攻撃")
        let condition = SearchCondition(requiredSkills: [attack.id: 3])
        let outcome = try oracle.reverseLookup(condition: condition, weapon: TestSupport.slotlessWeapon)
        guard case .charms(let suggestions) = outcome else {
            return XCTFail("護石候補が提示されるべき")
        }
        guard FileManager.default.fileExists(atPath: TestSupport.enumeratedDbPath) else {
            throw XCTSkip("enumerated.db未生成(tools/enumerate-charms/enumerate.pyを実行)")
        }
        let db = try SQLiteConnection(path: TestSupport.enumeratedDbPath)
        for suggestion in suggestions where suggestion.requirement.weaponSlots.isEmpty
            && suggestion.requirement.armorSlots.isEmpty {
            for (skillId, level) in suggestion.requirement.skills {
                var count = 0
                try db.query("""
                    SELECT COUNT(*) FROM EnumeratedCharm
                    WHERE rarity = \(suggestion.minimumRarity)
                      AND ((skill1Id = \(skillId) AND skill1Level >= \(level))
                        OR (skill2Id = \(skillId) AND skill2Level >= \(level))
                        OR (skill3Id = \(skillId) AND skill3Level >= \(level)))
                    """) { count = Int($0.int(0)) }
                XCTAssertGreaterThan(
                    count, 0,
                    "候補(スキル\(skillId) Lv\(level)+ レア\(suggestion.minimumRarity))が全列挙に存在しない")
            }
        }
    }

    func testRelaxationWhenCharmCannotHelp() throws {
        // 4部位要求のシリーズスキル2つ→護石では埋まらない→「外せば組める」代替提示(仕様3.2 手順5)
        let a = TestSupport.skill(named: "兇爪竜の力")
        let b = TestSupport.skill(named: "千刃竜の闘志")
        let condition = SearchCondition(requiredSkills: [a.id: 2, b.id: 2])
        let outcome = try oracle.reverseLookup(condition: condition)
        guard case .relaxations(let skillIds) = outcome else {
            return XCTFail("代替提示になるべき: \(outcome)")
        }
        XCTAssertEqual(Set(skillIds), Set([a.id, b.id]))
    }

    func testSlotRequirementSuggestion() throws {
        // 高レベル要求では「スキル+スロット」型の候補も出得る。要求の実在可能性のみ検証
        let attack = TestSupport.skill(named: "攻撃")
        let mind = TestSupport.skill(named: "見切り")
        let condition = SearchCondition(requiredSkills: [attack.id: 2, mind.id: 2])
        let outcome = try oracle.reverseLookup(condition: condition, weapon: TestSupport.slotlessWeapon)
        if case .charms(let suggestions) = outcome {
            for suggestion in suggestions {
                XCTAssertNotNil(
                    master.charmRules.minimumRarity(satisfying: suggestion.requirement),
                    "規則上あり得ない候補を提示している")
                XCTAssertTrue((5...8).contains(suggestion.minimumRarity))
            }
        }
    }
}
