import XCTest
@testable import MHSimulatorCore

/// 装備比較の期待値計算(仕様3.7)のテスト
final class ExpectedAttackCalculatorTests: XCTestCase {
    typealias Calc = ExpectedAttackCalculator
    typealias S = Calc.SkillIds

    private func eval(
        _ base: Int, _ aff: Int, atk: Int = 0, ce: Int = 0, cb: Int = 0,
        extra: [SkillId: Int] = [:], on: Set<Calc.Condition> = [],
        items: Calc.ItemSelection = .init(), kind: String? = nil
    ) -> Calc.Output {
        var skills = extra
        if atk > 0 { skills[S.attackBoost] = atk }
        if ce > 0 { skills[S.criticalEye] = ce }
        if cb > 0 { skills[S.criticalBoost] = cb }
        return Calc.evaluate(Calc.Input(
            baseAttack: base, weaponAffinity: aff, skills: skills, weaponKind: kind, conditions: on, items: items))
    }

    private func assertOutput(_ o: Calc.Output, _ attack: Int, _ affinity: Int, _ expected: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(o.attack, attack, "攻撃力", file: file, line: line)
        XCTAssertEqual(o.affinity, affinity, "会心率", file: file, line: line)
        XCTAssertEqual(o.expected, expected, accuracy: 0.05, "期待値", file: file, line: line)
    }

    // MARK: 仕様3.7 テストベクタ

    func testVectorsAlwaysOnSkills() {
        assertOutput(eval(200, 0), 200, 0, 200.0)
        assertOutput(eval(200, 30), 200, 30, 215.0)
        assertOutput(eval(200, 30, atk: 1), 203, 30, 218.2)
        assertOutput(eval(200, 30, ce: 1), 200, 34, 217.0)
        assertOutput(eval(200, 30, cb: 1), 200, 30, 216.8)
        assertOutput(eval(210, 0, atk: 5), 227, 0, 227.0)   // ×1.04 +9
        assertOutput(eval(210, 0, atk: 4), 222, 0, 222.0)   // ×1.02 +8
    }

    func testVectorsWeaknessExploit() {
        let wex1 = [S.weaknessExploit: 1]
        assertOutput(eval(200, 30, extra: wex1, on: [.weakSpot]), 200, 35, 217.5)
        assertOutput(eval(200, 30, extra: wex1, on: [.weakSpot, .wound]), 200, 38, 219.0)
        // 条件OFFなら効かない
        assertOutput(eval(200, 30, extra: wex1), 200, 30, 215.0)
    }

    func testVectorsAffinityCapAndNegative() {
        let neg = eval(200, -20, cb: 5)
        assertOutput(neg, 200, -20, 190.0)
        XCTAssertEqual(neg.critMultiplier, 0.75)
        let capped = eval(200, 90, ce: 5, cb: 3)
        assertOutput(capped, 200, 100, 268.0)
        XCTAssertTrue(capped.isAffinityCapped)
        XCTAssertFalse(neg.isAffinityCapped)
    }

    func testVectorsCombinedConditions() {
        let base = [S.weaknessExploit: 3]
        assertOutput(eval(210, 15, atk: 3, ce: 3, cb: 2, extra: base, on: [.weakSpot]), 217, 42, 245.3)
        let agi = base.merging([S.agitator: 3]) { a, _ in a }
        assertOutput(eval(210, 15, atk: 3, ce: 3, cb: 2, extra: agi, on: [.weakSpot, .enraged]), 229, 49, 263.8)
        let all = agi.merging([S.maximumMight: 1]) { a, _ in a }
        assertOutput(eval(210, 15, atk: 3, ce: 3, cb: 2, extra: all, on: [.weakSpot, .wound, .enraged, .maxMight]), 229, 69, 278.0)
        assertOutput(eval(210, 15, atk: 3, ce: 3, cb: 2, extra: [S.heroics: 5], on: [.heroics]), 280, 27, 303.4)
    }

    func testVectorsItems() {
        var items = Calc.ItemSelection()
        items.powercharm = true
        items.demondrug = .mega
        assertOutput(eval(210, 15, atk: 3, ce: 3, cb: 2, items: items), 230, 27, 249.3)
        items.demonPowder = true
        items.might = .pill
        items.moodyMeal = .large
        XCTAssertEqual(items.attackBonus, 6 + 7 + 10 + 25 + 15)
    }

    func testCompareExample() {
        // 比較例(仕様3.7): 攻撃特化 攻5/見2/超1/弱特3 有効部位 → 227・38%・×1.28 → 251.2
        let o = eval(210, 15, atk: 5, ce: 2, cb: 1, extra: [S.weaknessExploit: 3], on: [.weakSpot])
        assertOutput(o, 227, 38, 251.2)
        XCTAssertEqual(o.critMultiplier, 1.28)
        XCTAssertEqual(Calc.gainPercent(from: 245.3, to: 251.2), 2.4, accuracy: 0.05)
    }

    // MARK: 個別スキル

    func testBurstDependsOnWeaponGroup() {
        let burst = [S.burst: 5]
        XCTAssertEqual(eval(200, 0, extra: burst, on: [.burst], kind: "great-sword").attack, 218)
        XCTAssertEqual(eval(200, 0, extra: burst, on: [.burst], kind: "long-sword").attack, 218)
        XCTAssertEqual(eval(200, 0, extra: [S.burst: 1], on: [.burst], kind: "long-sword").attack, 208)
        XCTAssertEqual(eval(200, 0, extra: burst, on: [.burst], kind: "bow").attack, 210)
        XCTAssertEqual(eval(200, 0, extra: burst, on: [.burst], kind: nil).attack, 218)  // 武器なし=剣戟系
        // 兇爪竜の力も同じ条件(連撃発動中)で加算
        XCTAssertEqual(eval(200, 0, extra: [S.burst: 5, S.ebonyOdogaronsPower: 2], on: [.burst], kind: "hammer").attack, 236)
    }

    func testFrenzyOvercomeAddsMechanicAffinity() {
        // 無我の境地Lv3 + 克服中: ゲーム仕様+15% + 10%
        XCTAssertEqual(eval(200, 0, extra: [S.antivirus: 3], on: [.frenzyOvercome]).affinity, 25)
        // 黒蝕竜の力Ⅱ: 感染中 攻+10 / 克服中 攻+15(+会心15%)
        XCTAssertEqual(eval(200, 0, extra: [S.goreMagalasTyranny: 2], on: [.frenzyInfected]).attack, 210)
        let overcome = eval(200, 0, extra: [S.goreMagalasTyranny: 2], on: [.frenzyOvercome])
        XCTAssertEqual(overcome.attack, 215)
        XCTAssertEqual(overcome.affinity, 15)
        // Ⅰは攻撃力上昇なし
        XCTAssertEqual(eval(200, 0, extra: [S.goreMagalasTyranny: 1], on: [.frenzyInfected]).attack, 200)
    }

    func testMultipliersStackOnBaseAttack() {
        // 火事場Lv5 ×1.3 と 攻めの守勢Lv3 ×1.15 は基礎攻撃力にまとめて掛けてから加算(仕様3.7)
        let o = eval(200, 0, atk: 5, extra: [S.heroics: 5, S.offensiveGuard: 3], on: [.heroics, .offensiveGuard])
        // 200 × 1.04 × 1.3 × 1.15 = 310.96 → 310 + 9
        XCTAssertEqual(o.attack, 319)
    }

    func testFestivalPrayerOnlyAtRankTwo() {
        XCTAssertEqual(eval(200, 0, extra: [S.blossomdancePrayer: 1], on: [.festival]).attack, 200)
        XCTAssertEqual(eval(200, 0, extra: [S.blossomdancePrayer: 2], on: [.festival]).attack, 218)
    }

    // MARK: 状態行・排他・未計上

    func testRowsAreUnionInTableOrder() {
        let base: [SkillId: Int] = [S.attackBoost: 3, S.weaknessExploit: 3, S.maximumMight: 1, S.criticalDraw: 1]
        let compare: [SkillId: Int] = [S.agitator: 3, S.weaknessExploit: 2, S.punishingDraw: 2]
        let rows = Calc.rows(for: [base, compare])
        XCTAssertEqual(rows.map(\.condition), [.weakSpot, .wound, .enraged, .maxMight, .drawAttack])
        XCTAssertEqual(rows.last?.skillIds, [S.criticalDraw, S.punishingDraw])
        // 常時スキルは行にならない
        XCTAssertFalse(rows.contains { $0.skillIds.contains(S.attackBoost) })
        // 比較未選択(1装備)でも動く
        XCTAssertEqual(Calc.rows(for: [compare]).map(\.condition), [.weakSpot, .wound, .enraged, .drawAttack])
    }

    func testExclusiveConflicts() {
        XCTAssertEqual(Calc.conflicts(turningOn: .peakPerformance, active: [.resentment, .heroics, .weakSpot]), [.resentment, .heroics])
        XCTAssertEqual(Calc.conflicts(turningOn: .resentment, active: [.peakPerformance]), [.peakPerformance])
        XCTAssertEqual(Calc.conflicts(turningOn: .resentment, active: [.heroics]), [])  // 同一グループ内は両立
        XCTAssertEqual(Calc.conflicts(turningOn: .bubble, active: [.wet]), [.wet])
        XCTAssertEqual(Calc.conflicts(turningOn: .frenzyOvercome, active: [.frenzyInfected]), [.frenzyInfected])
        XCTAssertEqual(Calc.conflicts(turningOn: .resonanceFar, active: [.resonanceNear]), [.resonanceNear])
        XCTAssertEqual(Calc.conflicts(turningOn: .fortify2, active: [.fortify1]), [.fortify1])
        XCTAssertEqual(Calc.conflicts(turningOn: .weakSpot, active: [.wound, .enraged]), [])
    }

    func testUncountedSkills() {
        XCTAssertEqual(Calc.uncountedSkills(in: [S.seregiossTenacity: 2, S.attackBoost: 1]), [S.seregiossTenacity])
        XCTAssertEqual(Calc.uncountedSkills(in: [S.powerStone: 1]), [S.powerStone])
        XCTAssertTrue(Calc.uncountedSkills(in: [S.attackBoost: 5]).isEmpty)
    }

    // MARK: マスタとの突合

    func testTableSkillsExistInMasterWithMatchingMaxLevel() {
        let master = TestSupport.master
        for entry in Calc.table {
            guard let skill = master.skills[entry.id] else {
                XCTFail("マスタに無いスキルID: \(entry.id)"); continue
            }
            for (_, levels) in entry.effects where !levels.isEmpty {
                XCTAssertEqual(levels.count, skill.maxLevel, "\(skill.name) のレベル数が定数表と一致しない")
            }
            if let burst = entry.burstByGroup {
                for (_, levels) in burst { XCTAssertEqual(levels.count, skill.maxLevel, "\(skill.name)") }
            }
        }
        for id in Calc.uncountedSkillIds {
            XCTAssertNotNil(master.skills[id], "未計上スキルがマスタに無い: \(id)")
        }
    }

    /// 効果文に書かれている数値(全角)が定数表の値を含むことを確認する(TUで値が変わったら落ちる)
    func testTableValuesAppearInMasterEffectText() {
        let master = TestSupport.master
        for entry in Calc.table where entry.sourcedFromMaster {
            guard let skill = master.skills[entry.id] else { continue }
            for (_, levels) in entry.effects {
                for (index, effect) in levels.enumerated() {
                    let level = index + 1
                    guard let text = skill.levelEffects[level] else {
                        XCTFail("\(skill.name) Lv\(level) の効果文が無い"); continue
                    }
                    let numbers = Self.numbers(in: text)
                    var expected: [Double] = []
                    if effect.attackAdd != 0 { expected.append(Double(effect.attackAdd)) }
                    if effect.affinityAdd != 0 { expected.append(Double(effect.affinityAdd)) }
                    if effect.attackMul != 1 { expected.append(effect.attackMul) }
                    if let k = effect.critMultiplier { expected.append(k) }
                    for value in expected {
                        XCTAssertTrue(
                            numbers.contains { abs($0 - value) < 0.0001 },
                            "\(skill.name) Lv\(level): 定数 \(value) が効果文「\(text)」に無い")
                    }
                }
            }
        }
    }

    private static func numbers(in text: String) -> [Double] {
        let normalized = String(text.map { ch -> Character in
            switch ch {
            case "０"..."９": return Character(UnicodeScalar(ch.unicodeScalars.first!.value - 0xFF10 + 0x30)!)
            case "．": return "."
            default: return ch
            }
        })
        let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: range).compactMap {
            Range($0.range, in: normalized).flatMap { Double(normalized[$0]) }
        }
    }

    // MARK: Weapon(攻撃力・会心率)

    func testMasterWeaponsCarryAttackAndAffinity() {
        let master = TestSupport.master
        XCTAssertTrue(master.weapons.allSatisfy { $0.attackRaw > 0 })
        XCTAssertTrue(master.weapons.contains { $0.affinity != 0 })
    }

    func testWeaponDecodesWithoutAttackKeys() throws {
        // 2026-09-04以前のマイセットのスナップショット(attackRaw/affinityキーなし)
        let json = #"{"id":7,"kind":"great-sword","name":"x","rarity":8,"slots":[3],"skills":[]}"#
        let weapon = try JSONDecoder().decode(Weapon.self, from: Data(json.utf8))
        XCTAssertEqual(weapon.attackRaw, 0)
        XCTAssertEqual(weapon.affinity, 0)
        let roundTrip = try JSONDecoder().decode(Weapon.self, from: JSONEncoder().encode(
            Weapon(id: 1, kind: "bow", name: "b", rarity: 1, slots: [], skills: [:], attackRaw: 90, affinity: 5)))
        XCTAssertEqual(roundTrip.attackRaw, 90)
        XCTAssertEqual(roundTrip.affinity, 5)
    }
}
