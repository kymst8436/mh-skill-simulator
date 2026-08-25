import XCTest
@testable import MHSimulatorCore

/// 性能予算(仕様6.1)の粗い検証: 条件スキル5個+所持護石100個で3秒以内。
/// 基準機はiPhone(Q-9)なのでMac上の値は参考値だが、明確な劣化の検出に使う。
final class PerformanceTests: XCTestCase {
    let master = TestSupport.master
    lazy var engine = SearchEngine(master: master)

    /// 規則からあり得る護石を決定的に100個生成する(乱数シード不要の順回し)
    func makeOwnedCharms(_ count: Int) -> [Charm] {
        var charms: [Charm] = []
        let rules = master.charmRules
        outer: for pattern in rules.patterns {
            let groupIds = pattern.skillGroups.compactMap { $0 }
            let entryLists = groupIds.map { rules.groups[$0]!.sorted { $0.skillId < $1.skillId } }
            for offset in 0..<8 {
                var skills: [SkillId: Int] = [:]
                for entries in entryLists {
                    let entry = entries[(offset * 7) % entries.count]
                    if skills[entry.skillId] == nil {  // 同一スキル重複は規則上なし
                        skills[entry.skillId] = entry.level
                    }
                }
                let combo = pattern.slotCombos[offset % pattern.slotCombos.count]
                charms.append(Charm(
                    source: .owned(UUID()), name: "生成護石\(charms.count)",
                    skills: skills,
                    weaponSlots: combo.weaponSlots, armorSlots: combo.armorSlots))
                if charms.count >= count { break outer }
            }
        }
        return charms
    }

    func testSearchBudgetFiveSkills100Charms() throws {
        let condition = SearchCondition(requiredSkills: [
            TestSupport.skill(named: "龍耐性").id: 2,
            TestSupport.skill(named: "体力回復量ＵＰ").id: 1,
            TestSupport.skill(named: "防御").id: 3,
            TestSupport.skill(named: "回避性能").id: 2,
            TestSupport.skill(named: "耳栓").id: 1,
        ])
        let charms = makeOwnedCharms(100)
        XCTAssertEqual(charms.count, 100)

        let start = Date()
        let result = try engine.search(condition: condition, ownedCharms: charms)
        let elapsed = Date().timeIntervalSince(start)
        print("検索時間: \(String(format: "%.2f", elapsed))s / 結果: \(result.sets.count)件 (truncated=\(result.truncated))")
        XCTAssertLessThan(elapsed, 3.0, "性能予算超過(仕様6.1: 3秒以内)")
    }

    func testReverseLookupBudget() throws {
        // 逆引き: 0件確定から2秒以内(仕様6.1)
        let attack = TestSupport.skill(named: "攻撃")
        let condition = SearchCondition(requiredSkills: [attack.id: 3])
        let oracle = CharmOracle(engine: engine)
        let start = Date()
        _ = try oracle.reverseLookup(condition: condition)
        let elapsed = Date().timeIntervalSince(start)
        print("逆引き時間: \(String(format: "%.2f", elapsed))s")
        XCTAssertLessThan(elapsed, 2.0, "性能予算超過(仕様6.1: 2秒以内)")
    }
}
