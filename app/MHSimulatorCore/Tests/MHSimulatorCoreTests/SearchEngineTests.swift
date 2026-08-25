import XCTest
@testable import MHSimulatorCore

/// 装備検索(F-1)の検証。結果は独立検証器(ResultValidator)で再計算して固定する
final class SearchEngineTests: XCTestCase {
    let master = TestSupport.master
    lazy var engine = SearchEngine(master: master)
    lazy var validator = ResultValidator(master: master)

    func assertAllValid(
        _ result: SearchResult, condition: SearchCondition,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for set in result.sets {
            let violations = validator.validate(set, condition: condition)
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

    // MARK: - 固定・除外(2026-08-24追加)

    func testPinnedPieceIsAlwaysUsed() throws {
        let skillId = TestSupport.skill(named: "龍耐性").id
        let base = try engine.search(condition: SearchCondition(requiredSkills: [skillId: 1]))
        // 基準結果の先頭セットの頭部位を固定して再検索→全結果がその頭になる
        guard let pinnedHead = base.sets.first?.pieces[.head] else {
            return XCTFail("基準結果に頭部位がない")
        }
        let condition = SearchCondition(
            requiredSkills: [skillId: 1],
            pinnedPieceIds: [.head: pinnedHead.id])
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty)
        for set in result.sets {
            XCTAssertEqual(set.pieces[.head]?.id, pinnedHead.id)
        }
        assertAllValid(result, condition: condition)
    }

    func testExcludedPieceNeverAppears() throws {
        let skillId = TestSupport.skill(named: "龍耐性").id
        let base = try engine.search(condition: SearchCondition(requiredSkills: [skillId: 1]))
        let excludedIds = Set(base.sets.compactMap { $0.pieces[.head]?.id })
        let condition = SearchCondition(
            requiredSkills: [skillId: 1],
            excludedPieceIds: excludedIds)
        let result = try engine.search(condition: condition)
        for set in result.sets {
            if let head = set.pieces[.head] {
                XCTAssertFalse(excludedIds.contains(head.id))
            }
        }
        assertAllValid(result, condition: condition)
    }

    func testPinnedFixedCharmIsAlwaysUsed() throws {
        guard let charm = master.fixedCharms.first,
              case .fixed(let charmId, _) = charm.source else {
            return XCTFail("固定護石データがない")
        }
        let skillId = TestSupport.skill(named: "龍耐性").id
        let condition = SearchCondition(
            requiredSkills: [skillId: 1],
            pinnedFixedCharmId: charmId)
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty)
        for set in result.sets {
            guard case .fixed(let usedId, _) = set.charm.source else {
                return XCTFail("固定護石以外が使われた: \(set.charm.name)")
            }
            XCTAssertEqual(usedId, charmId)
        }
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

    func testWeaponContributesToSetBonus() throws {
        // 武器付与のシリーズスキルは発動部位数に加算される
        // (TU追加のアーティア武器等を想定。現データに実物が無いため合成武器で検証)
        let skill = TestSupport.skill(named: "兇爪竜の力")  // 2部位でLv1発動
        let weapon = Weapon(
            id: 999_999, kind: "great-sword", name: "テスト武器(シリーズスキル付き)",
            rarity: 8, slots: [], skills: [skill.id: 1])
        let condition = SearchCondition(requiredSkills: [skill.id: 1])
        let result = try engine.search(condition: condition, weapon: weapon)
        XCTAssertFalse(result.sets.isEmpty)
        assertAllValid(result, condition: condition)
        // 武器が1部位分を担うため、該当ボーナス持ちの防具は1部位で足りる組み合わせが存在する
        let minPieces = result.sets.map { set in
            set.pieces.values.filter { piece in
                master.armorSeries[piece.seriesId]?.setBonus?.skillId == skill.id
            }.count
        }.min() ?? .max
        XCTAssertEqual(minPieces, 1)
    }

    // MARK: - 武器スキルと護石

    func testAutoWeaponSolvesWeaponSkills() throws {
        // 武器未指定=「何の武器でも良い」(2026-08-24改訂)。
        // ガード性能3+ガード強化3は適切な武器(スキル持ちorスロット持ち)を自動選択して組める
        let condition = SearchCondition(requiredSkills: [
            TestSupport.skill(named: "ガード性能").id: 3,
            TestSupport.skill(named: "ガード強化").id: 3,
        ])
        let result = try engine.search(condition: condition)
        XCTAssertFalse(result.sets.isEmpty, "自動武器選択で組めるはず")
        assertAllValid(result, condition: condition)
        // 採用武器が結果に含まれる
        XCTAssertTrue(result.sets.allSatisfy { $0.weapon != nil })
    }

    func testSlotlessWeaponMakesWeaponSkillImpossible() throws {
        // スロット無し・スキル無しの武器を明示指定した場合、武器スキルは護石以外で埋まらない
        let condition = SearchCondition(requiredSkills: [TestSupport.skill(named: "攻撃").id: 1])
        let result = try engine.search(condition: condition, weapon: TestSupport.slotlessWeapon)
        XCTAssertTrue(result.sets.isEmpty)
    }

    func testOwnedCharmEnablesWeaponSkill() throws {
        // スロット無し武器でも、攻撃Lv1の所持護石を登録すれば組める(F-3→F-1の連携)
        let attack = TestSupport.skill(named: "攻撃")
        let charm = Charm(
            source: .owned(UUID()), name: "テスト護石",
            skills: [attack.id: 1], weaponSlots: [], armorSlots: [])
        let condition = SearchCondition(requiredSkills: [attack.id: 1])
        let result = try engine.search(
            condition: condition, weapon: TestSupport.slotlessWeapon, ownedCharms: [charm])
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
        assertAllValid(result, condition: condition)
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
