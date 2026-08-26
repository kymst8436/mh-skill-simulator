import XCTest
@testable import MHSimulatorCore

/// 充足ぎりぎりの重い条件での性能回帰テスト(2026-08-24)。
/// スキル10種(シリーズ+グループ含む)+武器固定の実報告ケース。
/// 装飾品割り当ての全体容量上界がないと葉の内部でバックトラックが爆発し、
/// デッドラインを無視して数分〜ハングしていた
final class HeavyConditionTests: XCTestCase {
    func testHeavyTenSkillConditionCompletesWithinDeadline() async throws {
        let master = TestSupport.master
        let engine = SearchEngine(master: master)
        let names: [(String, Int)] = [
            ("白熾龍の脈動", 1), ("栄光の誉れ", 1), ("ガード強化", 3), ("ガード性能", 3),
            ("スタミナ急速回復", 2), ("回復速度", 3), ("体力回復量ＵＰ", 3),
            ("火耐性", 3), ("精霊の加護", 3), ("腹減り耐性", 2),
        ]
        var required: [SkillId: Int] = [:]
        for (name, level) in names { required[TestSupport.skill(named: name).id] = level }
        guard let weapon = master.weapons.first(where: { $0.name == "激槍グラビモス" }) else {
            return XCTFail("武器が見つからない")
        }
        let condition = SearchCondition(requiredSkills: required)

        // アプリ実装と同じ「時間予算超過でタスクキャンセル」方式(協調キャンセルへの1本化。2026-08-26)
        let start = Date()
        let work = Task.detached(priority: .userInitiated) {
            try engine.search(condition: condition, weapon: weapon, options: .init(maxResults: 100))
        }
        let timer = Task {
            try? await Task.sleep(for: .seconds(5))
            work.cancel()
        }
        let result = try await work.value
        timer.cancel()
        let elapsed = Date().timeIntervalSince(start)

        // 時間予算+余裕内に必ず返る(以前はハング)
        XCTAssertLessThan(elapsed, 6.0, "探索がデッドラインを大きく超過")
        // この条件は実際には組める(全体容量上界の導入で高速に発見できる)
        XCTAssertFalse(result.sets.isEmpty)

        let validator = ResultValidator(master: master)
        for set in result.sets {
            let violations = validator.validate(set, condition: condition)
            XCTAssertTrue(violations.isEmpty,
                          "違反: \(violations.map(\.description).joined(separator: " / "))")
        }
    }
}
