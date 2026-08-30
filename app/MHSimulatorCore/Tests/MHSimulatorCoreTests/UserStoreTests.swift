import XCTest
@testable import MHSimulatorCore

/// user.db(仕様4.3 / 5章)の検証: CRUD・重複判定・AppState・破損復旧・1,000件性能
final class UserStoreTests: XCTestCase {
    var tempDir: URL!
    var dbPath: String { tempDir.appendingPathComponent("user.db").path }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeCharm(skillId: SkillId = 100, level: Int = 2) -> OwnedCharm {
        OwnedCharm(
            skills: [
                CharmRules.GroupEntry(skillId: skillId, level: level),
                CharmRules.GroupEntry(skillId: 200, level: 1),
            ],
            weaponSlots: [], armorSlots: [2, 1], rarity: 7, memo: "テスト")
    }

    func testInsertLoadRoundtrip() throws {
        let store = try UserStore(path: dbPath)
        XCTAssertFalse(store.didRecoverFromCorruption)
        let charm = makeCharm()
        try store.insert(charm)
        let loaded = try store.loadCharms()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, charm.id)
        XCTAssertEqual(loaded[0].skills, charm.skills)  // 枠順保持
        XCTAssertEqual(loaded[0].armorSlots, [2, 1])
        XCTAssertEqual(loaded[0].rarity, 7)
        XCTAssertEqual(loaded[0].memo, "テスト")
    }

    func testUpdateAndDelete() throws {
        let store = try UserStore(path: dbPath)
        var charm = makeCharm()
        try store.insert(charm)
        charm.memo = "更新済み"
        charm.skills = [CharmRules.GroupEntry(skillId: 300, level: 3)]
        try store.update(charm)
        let updated = try store.loadCharms()
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].memo, "更新済み")
        XCTAssertEqual(updated[0].skills.count, 1)

        try store.delete(id: charm.id)
        XCTAssertTrue(try store.loadCharms().isEmpty)
    }

    func testDuplicateDetection() throws {
        let store = try UserStore(path: dbPath)
        let charm = makeCharm()
        try store.insert(charm)
        // 同一構成の別個体は重複として検知(登録自体は許可される)
        let sameBuild = makeCharm()
        XCTAssertTrue(try store.hasDuplicate(of: sameBuild))
        // 自分自身は除外(編集時)
        XCTAssertFalse(try store.hasDuplicate(of: charm, excluding: charm.id))
        // レベル違いは別護石
        XCTAssertFalse(try store.hasDuplicate(of: makeCharm(level: 3)))
    }

    func testAppStateRoundtrip() throws {
        let store = try UserStore(path: dbPath)
        XCTAssertNil(try store.loadSelectedWeaponId())
        try store.saveSelectedWeaponId(42)
        XCTAssertEqual(try store.loadSelectedWeaponId(), 42)
        try store.saveSelectedWeaponId(nil)
        XCTAssertNil(try store.loadSelectedWeaponId())

        XCTAssertTrue(try store.loadLastSearchConditions().isEmpty)
        try store.saveLastSearchConditions([(skillId: -100, level: 3), (skillId: 5, level: 1)])
        let conditions = try store.loadLastSearchConditions()
        XCTAssertEqual(conditions.count, 2)
        XCTAssertEqual(conditions[0].skillId, -100)
        XCTAssertEqual(conditions[0].level, 3)
    }

    func testPersistenceAcrossReopen() throws {
        let charm = makeCharm()
        do {
            let store = try UserStore(path: dbPath)
            try store.insert(charm)
        }
        let reopened = try UserStore(path: dbPath)
        XCTAssertFalse(reopened.didRecoverFromCorruption)
        XCTAssertEqual(try reopened.loadCharms().first?.id, charm.id)
    }

    func testCorruptionRecovery() throws {
        // 壊れたファイルを置いて開く → 退避+空DB再作成+フラグ(仕様5.2)
        try Data("this is not a sqlite database at all........".utf8)
            .write(to: URL(fileURLWithPath: dbPath))
        let store = try UserStore(path: dbPath)
        XCTAssertTrue(store.didRecoverFromCorruption)
        XCTAssertTrue(try store.loadCharms().isEmpty)
        // 退避ファイルが残っている
        let siblings = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(siblings.contains { $0.contains("corrupt") }, "\(siblings)")
        // 復旧後は普通に書ける
        try store.insert(makeCharm())
        XCTAssertEqual(try store.loadCharms().count, 1)
    }

    func testThousandCharmsPerformance() throws {
        // 仕様6.1: 護石一覧1,000件で1秒以内
        let store = try UserStore(path: dbPath)
        for index in 0..<1000 {
            try store.insert(makeCharm(skillId: SkillId(index % 50), level: index % 3 + 1))
        }
        let start = Date()
        let loaded = try store.loadCharms()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(loaded.count, 1000)
        XCTAssertLessThan(elapsed, 1.0)
        print("護石1,000件読込: \(String(format: "%.3f", elapsed))s")
    }
    // MARK: - マイセット(画面設計4.15 2026-08-29追加)

    func makeEquipmentSet() -> EquipmentSet {
        let head = ArmorPiece(
            id: 1, seriesId: 10, kind: .head, name: "テスト頭",
            defenseMax: 60, resistances: [1, 2, 3, 4, 5], slots: [3, 1],
            limitBreakSlots: [3, 2], skills: [100: 2])
        let decoration = Decoration(id: 500, name: "攻撃珠", slotSize: 2, allowedOn: .armor, skills: [100: 1])
        let charm = Charm(
            source: .owned(UUID()), name: "攻撃+2",
            skills: [100: 2], weaponSlots: [], armorSlots: [1])
        let weapon = Weapon(id: 7, kind: "greatsword", name: "テスト大剣", rarity: 8, slots: [3], skills: [200: 1])
        return EquipmentSet(
            weapon: weapon,
            pieces: [.head: head],
            charm: charm,
            decorations: [DecorationAssignment(
                owner: .armor(.head), slotSize: 2, decoration: decoration, required: [100: 1])],
            activeSkills: [100: 5, 200: 1],
            totalDefenseMax: 60,
            totalResistances: [1, 2, 3, 4, 5],
            emptyWeaponSlots: [3],
            emptyArmorSlots: [1])
    }

    func testSavedSetRoundTrip() throws {
        let store = try UserStore(path: dbPath)
        let set = makeEquipmentSet()
        let item = SavedEquipmentSet(name: "テストセット", set: set, conditionSkills: [100: 5])
        try store.insertSavedSet(item)

        let loaded = try store.loadSavedSets()
        XCTAssertEqual(loaded.count, 1)
        let first = try XCTUnwrap(loaded.first)
        XCTAssertEqual(first.id, item.id)
        XCTAssertEqual(first.name, "テストセット")
        XCTAssertEqual(first.conditionSkills, [100: 5])
        // EquipmentSetのスナップショットが丸ごと復元される(値埋め込み)
        XCTAssertEqual(first.set.weapon?.name, "テスト大剣")
        XCTAssertEqual(first.set.weapon?.skills, [200: 1])
        XCTAssertEqual(first.set.pieces[.head]?.name, "テスト頭")
        XCTAssertEqual(first.set.pieces[.head]?.slots, [3, 1])
        XCTAssertEqual(first.set.charm.source, set.charm.source)
        XCTAssertEqual(first.set.charm.skills, [100: 2])
        XCTAssertEqual(first.set.decorations.count, 1)
        XCTAssertEqual(first.set.decorations[0].decoration.name, "攻撃珠")
        XCTAssertEqual(first.set.decorations[0].owner, .armor(.head))
        XCTAssertEqual(first.set.decorations[0].required, [100: 1])
        XCTAssertEqual(first.set.activeSkills, [100: 5, 200: 1])
        XCTAssertEqual(first.set.totalDefenseMax, 60)
        XCTAssertEqual(first.set.totalResistances, [1, 2, 3, 4, 5])
        XCTAssertEqual(first.set.emptyWeaponSlots, [3])
        XCTAssertEqual(first.set.emptyArmorSlots, [1])

        try store.deleteSavedSet(id: item.id)
        XCTAssertTrue(try store.loadSavedSets().isEmpty)
    }

    func testCountSavedSets() throws {
        let store = try UserStore(path: dbPath)
        XCTAssertEqual(try store.countSavedSets(), 0)
        let item = SavedEquipmentSet(name: "セット1", set: makeEquipmentSet())
        try store.insertSavedSet(item)
        try store.insertSavedSet(SavedEquipmentSet(name: "セット2", set: makeEquipmentSet()))
        XCTAssertEqual(try store.countSavedSets(), 2)
        try store.deleteSavedSet(id: item.id)
        XCTAssertEqual(try store.countSavedSets(), 1)
    }

    func testSavedSetOrderIsCreatedAtDescending() throws {
        let store = try UserStore(path: dbPath)
        let older = SavedEquipmentSet(
            name: "古いセット", set: makeEquipmentSet(),
            createdAt: Date(timeIntervalSinceNow: -100))
        let newer = SavedEquipmentSet(name: "新しいセット", set: makeEquipmentSet())
        try store.insertSavedSet(older)
        try store.insertSavedSet(newer)
        XCTAssertEqual(try store.loadSavedSets().map(\.name), ["新しいセット", "古いセット"])
    }

    func testWishlistRoundTrip() throws {
        let store = try UserStore(path: dbPath)
        let item = WishlistItem(
            skills: [
                CharmRules.GroupEntry(skillId: 100, level: 3),
                CharmRules.GroupEntry(skillId: 200, level: 1),
            ],
            weaponSlots: [2],
            armorSlots: [3, 1])
        try store.insertWishlistItem(item)

        let loaded = try store.loadWishlist()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
        XCTAssertEqual(loaded[0].skills.map(\.skillId), [100, 200])
        XCTAssertEqual(loaded[0].skills.map(\.level), [3, 1])
        XCTAssertEqual(loaded[0].weaponSlots, [2])
        XCTAssertEqual(loaded[0].armorSlots, [3, 1])
        XCTAssertEqual(loaded[0].requirement.skills, [100: 3, 200: 1])

        try store.deleteWishlistItem(id: item.id)
        XCTAssertTrue(try store.loadWishlist().isEmpty)
    }

}
