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
