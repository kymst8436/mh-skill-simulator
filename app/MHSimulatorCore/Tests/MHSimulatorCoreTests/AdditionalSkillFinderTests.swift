import XCTest
@testable import MHSimulatorCore

/// 追加スキル検索(F-9=仕様3.5)の検証
final class AdditionalSkillFinderTests: XCTestCase {
    let master = TestSupport.master
    lazy var engine = SearchEngine(master: master)
    lazy var finder = AdditionalSkillFinder(engine: engine)

    /// 護石なしでも組める防具スキル条件(攻撃系は武器スロ必須のためスロなし武器では組めない)
    private func makeCondition() -> SearchCondition {
        SearchCondition(requiredSkills: [
            TestSupport.skill(named: "龍耐性").id: 2,
            TestSupport.skill(named: "防御").id: 3,
        ])
    }

    func testEntriesAreFeasibleAndSorted() throws {
        let condition = makeCondition()
        let outcome = try finder.find(condition: condition, weapon: TestSupport.slotlessWeapon)

        XCTAssertTrue(outcome.isExhaustive)
        XCTAssertFalse(outcome.entries.isEmpty, "龍耐性2+防御3には追加余地があるはず")

        // 条件スキルは対象外(仕様3.5手順1)
        let conditionIds = Set(condition.requiredSkills.keys)
        for entry in outcome.entries {
            XCTAssertFalse(conditionIds.contains(entry.skillId))
            XCTAssertGreaterThanOrEqual(entry.maxAddableLevel, 1)
            XCTAssertLessThanOrEqual(entry.maxAddableLevel, master.skills[entry.skillId]!.maxLevel)
        }
        XCTAssertTrue(Set(outcome.notAddable).isDisjoint(with: conditionIds))

        // 提示順: 最大追加レベル降順→スキル名昇順(仕様Q-16)
        let pairs = outcome.entries.map { ($0.maxAddableLevel, master.skills[$0.skillId]!.name) }
        for (a, b) in zip(pairs, pairs.dropFirst()) {
            XCTAssertTrue(a.0 > b.0 || (a.0 == b.0 && a.1 <= b.1), "並び順違反: \(a) → \(b)")
        }

        // 主張レベルで実際に組めること(先頭5件で確認)
        for entry in outcome.entries.prefix(5) {
            var required = condition.requiredSkills
            required[entry.skillId] = entry.maxAddableLevel
            let result = try engine.search(
                condition: SearchCondition(requiredSkills: required),
                weapon: TestSupport.slotlessWeapon,
                options: SearchEngine.Options(maxResults: 1))
            XCTAssertFalse(result.sets.isEmpty,
                           "追加可能と判定したLvで組めない: \(master.skills[entry.skillId]!.name) Lv\(entry.maxAddableLevel)")
        }

        // 最大レベルの正しさ: maxLevel未満で確定した1件は、+1レベルでは組めないこと
        if let entry = outcome.entries.first(where: {
            $0.maxAddableLevel < master.skills[$0.skillId]!.maxLevel
        }) {
            var required = condition.requiredSkills
            required[entry.skillId] = entry.maxAddableLevel + 1
            let result = try engine.search(
                condition: SearchCondition(requiredSkills: required),
                weapon: TestSupport.slotlessWeapon,
                options: SearchEngine.Options(maxResults: 1))
            XCTAssertTrue(result.sets.isEmpty,
                          "最大と判定したLvの+1で組めてしまう: \(master.skills[entry.skillId]!.name)")
        }
    }

    func testIncludesBonusSkills() throws {
        // シリーズ/グループスキルも対象(仕様Q-14)
        let outcome = try finder.find(
            condition: makeCondition(), weapon: TestSupport.slotlessWeapon)
        XCTAssertTrue(outcome.entries.contains {
            let kind = master.skills[$0.skillId]!.kind
            return kind == .set || kind == .group
        }, "シリーズ/グループスキルの候補が1件も出ていない")
    }

    func testResumeContinuesFromCheckpoint() throws {
        let condition = makeCondition()
        let full = try finder.find(condition: condition, weapon: TestSupport.slotlessWeapon)
        guard let sample = full.entries.first else { return XCTFail("候補なし") }

        // 未判定1件だけのチェックポイントから再開: そのスキルのみ判定し、全体結果と一致する
        let checkpoint = AdditionalSkillFinder.Outcome(
            entries: [], notAddable: [], pending: [sample.skillId])
        let resumed = try finder.find(
            condition: condition, weapon: TestSupport.slotlessWeapon, resuming: checkpoint)
        XCTAssertEqual(resumed.targetCount, 1)
        XCTAssertTrue(resumed.isExhaustive)
        XCTAssertEqual(resumed.entries, [sample])

        // 確定済みは再計算せず引き継ぐ(pendingなし→即返る)
        let done = AdditionalSkillFinder.Outcome(
            entries: full.entries, notAddable: full.notAddable, pending: [])
        let carried = try finder.find(
            condition: condition, weapon: TestSupport.slotlessWeapon, resuming: done)
        XCTAssertEqual(carried, done)
    }

    func testCancelledFindReturnsPartialWithPending() async throws {
        // キャンセル済みタスク内では未判定を残して途中結果を返す(仕様3.5手順5)
        let finder = self.finder
        let condition = makeCondition()
        let work = Task.detached { () -> AdditionalSkillFinder.Outcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return try finder.find(condition: condition, weapon: TestSupport.slotlessWeapon)
        }
        let outcome = try await work.value
        XCTAssertFalse(outcome.isExhaustive)
        XCTAssertFalse(outcome.pending.isEmpty)
    }

    func testProgressCallbackCountsUp() throws {
        let condition = makeCondition()
        final class Box: @unchecked Sendable { var values: [(Int, Int)] = [] }
        let box = Box()
        let outcome = try finder.find(
            condition: condition, weapon: TestSupport.slotlessWeapon,
            onSkillDetermined: { box.values.append(($0, $1)) })
        XCTAssertEqual(box.values.count, outcome.determinedCount)
        XCTAssertEqual(box.values.last?.0, outcome.determinedCount)
        XCTAssertEqual(box.values.last?.1, outcome.targetCount)
        // 単調増加
        for (a, b) in zip(box.values, box.values.dropFirst()) {
            XCTAssertEqual(b.0, a.0 + 1)
        }
    }
}
