import XCTest
@testable import MHSimulatorCore

/// 装備検索(F-1)の検証。結果は独立検証器(ResultValidator)で再計算して固定する
final class SearchEngineTests: XCTestCase {
    let master = TestSupport.master
    lazy var engine = SearchEngine(master: master)
    lazy var validator = ResultValidator(master: master)

    func assertAllValid(
        _ result: SearchResult, condition: SearchCondition, weapon: Weapon? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for set in result.sets {
            let violations = validator.validate(set, condition: condition, weapon: weapon)
            XCTAssertTrue(violations.isEmpty,
                          "違反: \(violations.map(\.description).joined(separator: " / "))",
                          file: file, line: line)
        }
    }

    // MARK: - 基本ケース

    func testSingleArmorSkillReturnsResults() throws {
        let condition = SearchCondition(requiredSkills: [TestSupport.skill(named: "龍耐性").id: 1])
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty)
        assertAllValid(result, condition: condition)
    }

    func testBroadConditionTruncatesAt100() throws {
        // 条件1個・低レベルは大量ヒット→上限打ち切り+打ち切り明示(仕様3.1エッジケース)
        let condition = SearchCondition(requiredSkills: [TestSupport.skill(named: "龍耐性").id: 1])
        let result = try engine.search(condition: condition)
        XCTAssertEqual(result.sets.count, 100)
        XCTAssertTrue(result.truncated)
        // 防御力maxの高い順(仕様Q-3)
        let defenses = result.sets.map(\.totalDefenseMax)
        XCTAssertEqual(defenses, defenses.sorted(by: >))
    }

    func testMultiSkillConditionValidates() throws {
        let condition = SearchCondition(requiredSkills: [
            TestSupport.skill(named: "龍耐性").id: 2,
            TestSupport.skill(named: "体力回復量ＵＰ").id: 1,
        ])
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty)
        assertAllValid(result, condition: condition)
    }

    func testEmptyConditionThrows() {
        XCTAssertThrowsError(try engine.search(condition: SearchCondition(requiredSkills: [:]))) {
            XCTAssertEqual($0 as? SearchError, .emptyCondition)
        }
    }

    func testLevelExceedsMaxThrows() {
        let skill = TestSupport.skill(named: "龍耐性")
        XCTAssertThrowsError(try engine.search(
            condition: SearchCondition(requiredSkills: [skill.id: skill.maxLevel + 1]))) {
            XCTAssertEqual($0 as? SearchError, .levelExceedsMax(skill.id))
        }
    }

    // MARK: - シリーズ/グループスキル

    func testSetBonusCondition() throws {
        // シリーズスキルLv1は2部位で発動。結果の全装備が発動条件を満たすことを独立検証
        let skill = TestSupport.skill(named: "兇爪竜の力")
        XCTAssertEqual(skill.kind, .set)
        let condition = SearchCondition(requiredSkills: [skill.id: 1])
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty)
        assertAllValid(result, condition: condition)
        // 2部位以上が該当ボーナスを持つこと
        for set in result.sets {
            let count = set.pieces.values.filter { piece in
                let series = master.armorSeries[piece.seriesId]
                return series?.setBonus?.skillId == skill.id
            }.count
            XCTAssertGreaterThanOrEqual(count, 2)
        }
    }

    func testConflictingSetBonusesReturnEmpty() throws {
        // 4部位要求のシリーズスキル2つは5部位に収まらない→探索せず/即0件
        let a = TestSupport.skill(named: "兇爪竜の力")
        let b = TestSupport.skill(named: "千刃竜の闘志")
        let condition = SearchCondition(requiredSkills: [a.id: 2, b.id: 2])
        let result = try engine.search(condition: condition)
        XCTAssertTrue(result.sets.isEmpty)
    }

    // MARK: - 武器スキルと護石

    func testWeaponSkillWithoutWeaponOrCharmIsImpossible() throws {
        // 武器スキルは防具・固定護石から出ない(データ実測)ため、武器未選択・護石なしでは組めない
        let condition = SearchCondition(requiredSkills: [TestSupport.skill(named: "攻撃").id: 1])
        let result = try engine.search(condition: condition)
        XCTAssertTrue(result.sets.isEmpty)
    }

    func testOwnedCharmEnablesWeaponSkill() throws {
        // 攻撃Lv1の所持護石を登録すれば組める(F-3→F-1の連携)
        let attack = TestSupport.skill(named: "攻撃")
        let charm = Charm(
            source: .owned(UUID()), name: "テスト護石",
            skills: [attack.id: 1], weaponSlots: [], armorSlots: [])
        let condition = SearchCondition(requiredSkills: [attack.id: 1])
        let result = try engine.search(condition: condition, ownedCharms: [charm])
        XCTAssertFalse(result.sets.isEmpty)
        assertAllValid(result, condition: condition)
        for set in result.sets {
            XCTAssertEqual(set.charm.source, charm.source)
        }
    }

    func testWeaponSlotsHostWeaponDecorations() throws {
        // 武器選択でそのスロットに武器装飾品を挿して武器スキルを発動できる
        let attack = TestSupport.skill(named: "攻撃")
        guard let attackDeco = master.decorations.first(where: {
            $0.allowedOn == .weapon && ($0.skills[attack.id] ?? 0) > 0
        }) else { return XCTFail("攻撃の武器装飾品が見つからない") }
        guard let weapon = master.weapons.first(where: {
            $0.slots.contains { $0 >= attackDeco.slotSize }
        }) else { return XCTFail("スロット付き武器が見つからない") }

        let condition = SearchCondition(requiredSkills: [attack.id: 1])
        let result = try engine.search(condition: condition, weapon: weapon)
        XCTAssertFalse(result.sets.isEmpty)
        assertAllValid(result, condition: condition, weapon: weapon)
    }

    // MARK: - 既知の正解ビルド(仕様3.4 手順6)

    func testKnownBuildIsFound() throws {
        // 実データから「ある5部位の組み合わせ」を正解として作り、その発動スキルで検索して再発見できるか
        let series = master.armorSeries.values
            .filter { series in
                ArmorPieceKind.allCases.allSatisfy { kind in
                    master.armorPieces.contains { $0.seriesId == series.id && $0.kind == kind }
                }
            }
            .sorted { $0.rarity != $1.rarity ? $0.rarity > $1.rarity : $0.id < $1.id }
            .first!
        let pieces = ArmorPieceKind.allCases.map { kind in
            master.armorPieces.first { $0.seriesId == series.id && $0.kind == kind }!
        }
        var totals: [SkillId: Int] = [:]
        for piece in pieces {
            for (skillId, level) in piece.skills { totals[skillId, default: 0] += level }
        }
        // 上位2スキル(armor種のみ・maxLevelクリップ)を条件にする
        let targets = totals
            .compactMap { skillId, level -> (SkillId, Int)? in
                guard let skill = master.skills[skillId], skill.kind == .armor else { return nil }
                return (skillId, min(level, skill.maxLevel))
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(2)
        let condition = SearchCondition(requiredSkills: Dictionary(uniqueKeysWithValues: Array(targets)))
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty, "\(series.name)の発動スキルで検索したのに0件")
        assertAllValid(result, condition: condition)
    }
}
