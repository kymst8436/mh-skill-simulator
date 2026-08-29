import XCTest
@testable import MHSimulatorCore

/// 装飾品の除外(F-7拡張)と必要分記録・代替候補列挙(仕様3.1手順5。2026-08-29)の検証
final class DecorationExclusionTests: XCTestCase {
    let master = TestSupport.master
    var engine: SearchEngine { SearchEngine(master: master) }

    /// 攻撃スキル(必ず装飾品が存在する)のID
    private var attackId: SkillId { TestSupport.skill(named: "攻撃").id }

    // MARK: - 必要分の記録

    func testAssignRecordsRequiredPortion() {
        // 複合珠(A+B)で不足Aのみを埋める → requiredにはAだけが記録される
        let skillA: SkillId = 1
        let skillB: SkillId = 2
        let compound = Decoration(
            id: 10, name: "複合珠", slotSize: 3, allowedOn: .armor,
            skills: [skillA: 1, skillB: 1])
        let catalog = DecorationAssigner.Catalog(
            decorations: [compound], targetSkills: [skillA, skillB])
        let result = DecorationAssigner.assign(
            deficits: [skillA: 1],
            slots: [.init(owner: .armor(.head), size: 3)],
            catalog: catalog)
        guard case .assigned(let assignment) = result else {
            return XCTFail("割り当てが成立するはず")
        }
        XCTAssertEqual(assignment.count, 1)
        XCTAssertEqual(assignment[0].required, [skillA: 1], "Bは不足していないので必要分に含まれない")
    }

    func testAssignRecordsPartialConsumption() {
        // 不足A:1に対しLv2の珠を挿す → 必要分は1(珠の寄与2ではなく消費した分)
        let skillA: SkillId = 1
        let big = Decoration(id: 11, name: "大珠", slotSize: 2, allowedOn: .armor, skills: [skillA: 2])
        let catalog = DecorationAssigner.Catalog(decorations: [big], targetSkills: [skillA])
        let result = DecorationAssigner.assign(
            deficits: [skillA: 1],
            slots: [.init(owner: .armor(.chest), size: 2)],
            catalog: catalog)
        guard case .assigned(let assignment) = result else {
            return XCTFail("割り当てが成立するはず")
        }
        XCTAssertEqual(assignment[0].required, [skillA: 1])
    }

    // MARK: - 除外の適用

    func testExcludedDecorationsRemovedFromCatalog() throws {
        let excluded = Set(master.decorations.filter { $0.skills[attackId] != nil }.map(\.id))
        XCTAssertFalse(excluded.isEmpty, "攻撃に寄与する装飾品が存在する前提")
        let prepared = try XCTUnwrap(engine.prepare(
            condition: SearchCondition(
                requiredSkills: [attackId: 1],
                excludedDecorationIds: excluded),
            weapon: TestSupport.slotlessWeapon, ownedCharms: []))
        for size in 1...3 {
            for slot in [DecorationAssigner.Slot(owner: .weapon, size: size),
                         DecorationAssigner.Slot(owner: .armor(.head), size: size)] {
                XCTAssertTrue(
                    prepared.catalog.options(for: slot).allSatisfy { !excluded.contains($0.id) },
                    "除外装飾品はカタログに残らない")
            }
        }
        XCTAssertEqual(prepared.excludedDecorationIds, excluded)
    }

    func testSearchResultsNeverUseExcludedDecorations() throws {
        let excluded = Set(master.decorations.filter { $0.skills[attackId] != nil }.map(\.id))
        let result = try engine.search(
            condition: SearchCondition(
                requiredSkills: [attackId: 2],
                excludedDecorationIds: excluded),
            weapon: TestSupport.slotlessWeapon,
            options: SearchEngine.Options(maxResults: 20))
        for set in result.sets {
            XCTAssertTrue(
                set.decorations.allSatisfy { !excluded.contains($0.decoration.id) },
                "検索結果に除外装飾品が使われていない")
        }
    }

    // MARK: - 代替候補の列挙

    func testAlternativeDecorationsListing() throws {
        // 実データから「同一スキルを満たせる珠が2種類以上ある」組を探して検証する
        let sample = try XCTUnwrap(master.decorations.first { deco in
            deco.skills.contains { skillId, _ in
                master.decorations.filter {
                    $0.allowedOn == deco.allowedOn && ($0.skills[skillId] ?? 0) >= 1
                }.count >= 2
            }
        }, "代替が存在する装飾品が実データにあるはず")
        let (skillId, _) = sample.skills.first { skillId, _ in
            master.decorations.filter {
                $0.allowedOn == sample.allowedOn && ($0.skills[skillId] ?? 0) >= 1
            }.count >= 2
        }!

        let alternatives = master.decorations(
            satisfying: [skillId: 1], target: sample.allowedOn, maxSize: 3)
        XCTAssertGreaterThanOrEqual(alternatives.count, 2)
        XCTAssertTrue(alternatives.allSatisfy { ($0.skills[skillId] ?? 0) >= 1 })

        // 除外すると候補から消える
        let withoutSample = master.decorations(
            satisfying: [skillId: 1], target: sample.allowedOn, maxSize: 3,
            excluding: [sample.id])
        XCTAssertFalse(withoutSample.contains { $0.id == sample.id })

        // スロットサイズ制約: 珠のサイズより小さい枠には入らない
        let tight = master.decorations(
            satisfying: [skillId: 1], target: sample.allowedOn, maxSize: 0)
        XCTAssertTrue(tight.isEmpty)
    }
}
