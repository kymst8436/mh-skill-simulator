import XCTest
@testable import MHSimulatorCore

/// 検索前スクリーニング(確定不可能の即時検知)の検証。
/// 大原則: 違反あり=100%組めない、が絶対条件。組める条件を誤検知したら仕様違反
final class FeasibilityScreenerTests: XCTestCase {
    let master = TestSupport.master
    lazy var engine = SearchEngine(master: master)
    lazy var screener = FeasibilityScreener(master: master)

    func condition(_ names: [(String, Int)]) -> SearchCondition {
        var required: [SkillId: Int] = [:]
        for (name, level) in names { required[TestSupport.skill(named: name).id] = level }
        return SearchCondition(requiredSkills: required)
    }

    // MARK: - 検知ケース(確定不可能)

    func testBonusPieceOverloadDetected() throws {
        // グループスキル3つ(各3部位)=9部位 > 防具5部位。武器はスキルなしで固定
        let cond = condition([("ヌシの魂", 1), ("ヌシの誇り", 1), ("ヌシの憤激", 1)])
        let violations = screener.diagnose(condition: cond, weapon: TestSupport.slotlessWeapon)
        guard case .bonusPieces(let required, let capacity)? = violations.first else {
            return XCTFail("ボーナス部位超過を検知すべき: \(violations)")
        }
        XCTAssertEqual(required, 9)
        XCTAssertEqual(capacity, 5)
        // 検索でも本当に0件(確定)であることを相互検証
        let result = try engine.search(
            condition: cond, weapon: TestSupport.slotlessWeapon,
            options: .init(maxResults: 1))
        XCTAssertTrue(result.sets.isEmpty)
        XCTAssertFalse(result.truncated)
    }

    func testWeaponSkillOverloadDetected() throws {
        // 武器スキル12レベルをスロットなし武器で要求 → 護石(最大4+スロ①)でも届かない
        let cond = condition([("ガード性能", 3), ("砲術", 3), ("攻めの守勢", 3), ("攻撃", 3)])
        let violations = screener.diagnose(condition: cond, weapon: TestSupport.slotlessWeapon)
        guard case .weaponSkills(let demand, let capacity)? = violations.first else {
            return XCTFail("武器スキル超過を検知すべき: \(violations)")
        }
        XCTAssertEqual(demand, 12)
        XCTAssertLessThan(capacity, demand)
        let result = try engine.search(
            condition: cond, weapon: TestSupport.slotlessWeapon,
            options: .init(maxResults: 1))
        XCTAssertTrue(result.sets.isEmpty)
        XCTAssertFalse(result.truncated)
    }

    // MARK: - 健全性(組める条件・不明な条件を誤検知しない)

    func testFeasibleConditionsAreNotFlagged() throws {
        // 実際に組める条件(検索で確認)は違反ゼロでなければならない
        let cases: [(String, [(String, Int)], String?)] = [
            ("軽い条件", [("攻撃", 1)], nil),
            ("5スキル", [("龍耐性", 2), ("体力回復量ＵＰ", 1), ("防御", 3),
                       ("回避性能", 2), ("耳栓", 1)], nil),
            ("重い10スキル", [("白熾龍の脈動", 1), ("栄光の誉れ", 1), ("ガード強化", 3),
                          ("ガード性能", 3), ("スタミナ急速回復", 2), ("回復速度", 3),
                          ("体力回復量ＵＰ", 3), ("火耐性", 3), ("精霊の加護", 3),
                          ("腹減り耐性", 2)], "激槍グラビモス"),
        ]
        for (label, names, weaponName) in cases {
            let weapon = weaponName.flatMap { name in master.weapons.first { $0.name == name } }
            let cond = condition(names)
            let result = try engine.search(
                condition: cond, weapon: weapon, options: .init(maxResults: 1))
            XCTAssertFalse(result.sets.isEmpty, "[\(label)] 前提が崩れている(組めるはず)")
            let violations = screener.diagnose(condition: cond, weapon: weapon)
            XCTAssertTrue(violations.isEmpty, "[\(label)] 組める条件を誤検知: \(violations)")
        }
    }

    func testBorderlineImpossibleConditionIsNotFlagged() {
        // 実報告の15スキル条件: 実際は組めないが、証明には全探索が必要なクラス。
        // スクリーナーは「確実に不可能」とは言えないため違反を出さない(片側判定の記録)
        let cond = condition([
            ("ガード性能", 3), ("砲術", 3), ("砲弾装填", 2), ("耳栓", 2),
            ("連撃", 5), ("挑戦者", 5), ("攻めの守勢", 3), ("逆襲", 3),
            ("白熾龍の脈動", 2), ("ヌシの魂", 1),
            ("回避距離ＵＰ", 2), ("回復速度", 2), ("体力回復量ＵＰ", 2),
            ("アイテム使用強化", 3), ("攻撃", 2),
        ])
        let weapon = Weapon(
            id: -1, kind: "custom", name: "カスタム武器", rarity: 8,
            slots: [3, 3, 3],
            skills: [
                TestSupport.skill(named: "白熾龍の脈動").id: 1,
                TestSupport.skill(named: "ヌシの魂").id: 1,
            ])
        XCTAssertTrue(screener.diagnose(condition: cond, weapon: weapon).isEmpty)
    }

    func testBonusOverloadOnTopOfReportedConditionIsFlagged() {
        // 実報告条件にグループスキルをもう1つ足すと部位数が確定オーバーする
        let cond = condition([
            ("白熾龍の脈動", 2), ("ヌシの魂", 1), ("ヌシの誇り", 1), ("攻撃", 2),
        ])
        let weapon = Weapon(
            id: -1, kind: "custom", name: "カスタム武器", rarity: 8,
            slots: [3, 3, 3],
            skills: [
                TestSupport.skill(named: "白熾龍の脈動").id: 1,
                TestSupport.skill(named: "ヌシの魂").id: 1,
            ])
        let violations = screener.diagnose(condition: cond, weapon: weapon)
        guard case .bonusPieces(let required, let capacity)? = violations.first else {
            return XCTFail("ボーナス部位超過を検知すべき: \(violations)")
        }
        // 脈動Lv2=4部位(武器1)+ヌシの魂3部位(武器1)+ヌシの誇り3部位 = 3+2+3 = 8 > 5
        XCTAssertEqual(required, 8)
        XCTAssertEqual(capacity, 5)
    }

    func testEmptyConditionHasNoViolations() {
        XCTAssertTrue(screener.diagnose(
            condition: SearchCondition(requiredSkills: [:]), weapon: nil).isEmpty)
    }

    func testPerformanceIsInstant() {
        // 条件編集のたびに呼ぶ前提: 15スキルの診断が十分速いこと(debugでも数十ms以内)
        let cond = condition([
            ("ガード性能", 3), ("砲術", 3), ("砲弾装填", 2), ("耳栓", 2),
            ("連撃", 5), ("挑戦者", 5), ("攻めの守勢", 3), ("逆襲", 3),
            ("白熾龍の脈動", 2), ("ヌシの魂", 1),
            ("回避距離ＵＰ", 2), ("回復速度", 2), ("体力回復量ＵＰ", 2),
            ("アイテム使用強化", 3), ("攻撃", 2),
        ])
        let start = Date()
        for _ in 0..<10 {
            _ = screener.diagnose(condition: cond, weapon: nil)
        }
        let elapsed = Date().timeIntervalSince(start) / 10
        print("診断時間: \(String(format: "%.1f", elapsed * 1000))ms/回")
        XCTAssertLessThan(elapsed, 0.1)
    }
}
