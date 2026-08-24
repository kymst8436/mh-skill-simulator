import Foundation
import SQLite3

/// 所持護石(仕様4.3)。スキルは規則の枠順(スキル1→3)を保持する
public struct OwnedCharm: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var skills: [CharmRules.GroupEntry]  // 最大3・枠順
    public var weaponSlots: [Int]
    public var armorSlots: [Int]
    public var rarity: Int?
    public var memo: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        skills: [CharmRules.GroupEntry],
        weaponSlots: [Int] = [],
        armorSlots: [Int] = [],
        rarity: Int? = nil,
        memo: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.skills = skills
        self.weaponSlots = weaponSlots
        self.armorSlots = armorSlots
        self.rarity = rarity
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 検索エンジン用のCharmへ変換(nameは表示名。アプリ側でスキル名から組み立てる)
    public func asCharm(name: String) -> Charm {
        var skillMap: [SkillId: Int] = [:]
        for entry in skills {
            skillMap[entry.skillId, default: 0] += entry.level
        }
        return Charm(
            source: .owned(id), name: name,
            skills: skillMap,
            weaponSlots: weaponSlots, armorSlots: armorSlots)
    }

    /// 完全一致(重複登録警告の判定。仕様3.3 手順6)
    public func isSameCharm(as other: OwnedCharm) -> Bool {
        skills == other.skills
            && weaponSlots.sorted() == other.weaponSlots.sorted()
            && armorSlots.sorted() == other.armorSlots.sorted()
            && rarity == other.rarity
    }
}

/// user.db(仕様4.3 / 5章)。WALモード・1操作1トランザクション。
/// 起動時にintegrity_checkを行い、破損時は退避→再作成→通知(didRecoverFromCorruption)。
/// SQLiteアクセスは素のC API(Q-5改訂 2026-08-24: GRDB仮決定を撤回し依存ゼロを維持)。
public final class UserStore {
    public static let schemaVersion = 3  // v3: AppState.searchFilters追加(2026-08-24)

    public enum StoreError: Error {
        case cannotOpen(String)
        case sqlite(String)
    }

    /// 破損検出→初期化からの復旧が起きたか(画面設計 ダイアログ5の表示判定)
    public private(set) var didRecoverFromCorruption = false

    private var handle: OpaquePointer?
    private let path: String

    public init(path: String) throws {
        self.path = path
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)

        do {
            try open()
            if try isCorrupted() {
                try recoverFromCorruption()
            }
        } catch {
            // 開けない・検査不能も破損として扱い、退避→再作成(仕様5.2 手順2)
            try recoverFromCorruption()
        }
        try migrateIfNeeded()
    }

    deinit { sqlite3_close(handle) }

    // MARK: - 護石CRUD(1操作=1トランザクション)

    /// 登録日時降順(画面設計4.6)
    public func loadCharms() throws -> [OwnedCharm] {
        var skillsById: [String: [(Int, CharmRules.GroupEntry)]] = [:]
        try query("SELECT ownedCharmId, position, skillId, level FROM OwnedCharmSkill") { stmt in
            let id = String(cString: sqlite3_column_text(stmt, 0))
            skillsById[id, default: []].append((
                Int(sqlite3_column_int64(stmt, 1)),
                CharmRules.GroupEntry(
                    skillId: SkillId(sqlite3_column_int64(stmt, 2)),
                    level: Int(sqlite3_column_int64(stmt, 3)))))
        }
        var charms: [OwnedCharm] = []
        try query("""
            SELECT id, weaponSlots, armorSlots, rarity, memo, createdAt, updatedAt
            FROM OwnedCharm ORDER BY createdAt DESC
            """) { stmt in
            let idText = String(cString: sqlite3_column_text(stmt, 0))
            charms.append(OwnedCharm(
                id: UUID(uuidString: idText) ?? UUID(),
                skills: (skillsById[idText] ?? []).sorted { $0.0 < $1.0 }.map(\.1),
                weaponSlots: Self.decodeSlots(String(cString: sqlite3_column_text(stmt, 1))),
                armorSlots: Self.decodeSlots(String(cString: sqlite3_column_text(stmt, 2))),
                rarity: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, 3)),
                memo: String(cString: sqlite3_column_text(stmt, 4)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))))
        }
        return charms
    }

    public func insert(_ charm: OwnedCharm) throws {
        try transaction {
            try writeCharm(charm, isUpdate: false)
        }
    }

    public func update(_ charm: OwnedCharm) throws {
        try transaction {
            try exec("DELETE FROM OwnedCharmSkill WHERE ownedCharmId = ?", [.text(charm.id.uuidString)])
            try exec("DELETE FROM OwnedCharm WHERE id = ?", [.text(charm.id.uuidString)])
            var updated = charm
            updated.updatedAt = Date()
            try writeCharm(updated, isUpdate: true)
        }
    }

    public func delete(id: UUID) throws {
        try transaction {
            try exec("DELETE FROM OwnedCharmSkill WHERE ownedCharmId = ?", [.text(id.uuidString)])
            try exec("DELETE FROM OwnedCharm WHERE id = ?", [.text(id.uuidString)])
        }
    }

    /// 完全一致の登録済み護石があるか(重複登録警告。登録自体は許可=複数所持できる)
    public func hasDuplicate(of charm: OwnedCharm, excluding excludedId: UUID? = nil) throws -> Bool {
        try loadCharms().contains { $0.id != excludedId && $0.isSameCharm(as: charm) }
    }

    private func writeCharm(_ charm: OwnedCharm, isUpdate: Bool) throws {
        try exec("""
            INSERT INTO OwnedCharm (id, weaponSlots, armorSlots, rarity, memo, createdAt, updatedAt)
            VALUES (?,?,?,?,?,?,?)
            """, [
            .text(charm.id.uuidString),
            .text(Self.encodeSlots(charm.weaponSlots)),
            .text(Self.encodeSlots(charm.armorSlots)),
            charm.rarity.map { .int(Int64($0)) } ?? .null,
            .text(charm.memo),
            .real(charm.createdAt.timeIntervalSince1970),
            .real(charm.updatedAt.timeIntervalSince1970),
        ])
        for (position, entry) in charm.skills.enumerated() {
            try exec("""
                INSERT INTO OwnedCharmSkill (ownedCharmId, position, skillId, level)
                VALUES (?,?,?,?)
                """, [
                .text(charm.id.uuidString),
                .int(Int64(position)),
                .int(Int64(entry.skillId)),
                .int(Int64(entry.level)),
            ])
        }
    }

    // MARK: - AppState(仕様4.3)

    public func loadSelectedWeaponId() throws -> Int64? {
        var result: Int64?
        try query("SELECT selectedWeaponId FROM AppState WHERE id = 1") { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                result = sqlite3_column_int64(stmt, 0)
            }
        }
        return result
    }

    public func saveSelectedWeaponId(_ id: Int64?) throws {
        try transaction {
            try exec("UPDATE AppState SET selectedWeaponId = ? WHERE id = 1",
                     [id.map { .int($0) } ?? .null])
        }
    }

    /// カスタム武器設定(JSON。アプリ側で形式を定義)
    public func loadCustomWeaponJSON() throws -> String? {
        var json: String?
        try query("SELECT customWeapon FROM AppState WHERE id = 1") { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                json = String(cString: sqlite3_column_text(stmt, 0))
            }
        }
        return json
    }

    public func saveCustomWeaponJSON(_ json: String?) throws {
        try transaction {
            try exec("UPDATE AppState SET customWeapon = ? WHERE id = 1",
                     [json.map { .text($0) } ?? .null])
        }
    }

    /// 固定・除外設定(JSON。アプリ側で形式を定義。2026-08-24追加)
    public func loadSearchFiltersJSON() throws -> String? {
        var json: String?
        try query("SELECT searchFilters FROM AppState WHERE id = 1") { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                json = String(cString: sqlite3_column_text(stmt, 0))
            }
        }
        return json
    }

    public func saveSearchFiltersJSON(_ json: String?) throws {
        try transaction {
            try exec("UPDATE AppState SET searchFilters = ? WHERE id = 1",
                     [json.map { .text($0) } ?? .null])
        }
    }

    /// 最終検索条件(スキルId+目標レベルの配列をJSONで保持)
    public func loadLastSearchConditions() throws -> [(skillId: SkillId, level: Int)] {
        var json: String?
        try query("SELECT lastSearchConditions FROM AppState WHERE id = 1") { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                json = String(cString: sqlite3_column_text(stmt, 0))
            }
        }
        guard let json,
              let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([[String: Int64]].self, from: data) else { return [] }
        return rows.compactMap { row in
            guard let skillId = row["skillId"], let level = row["level"] else { return nil }
            return (SkillId(truncatingIfNeeded: skillId), Int(level))
        }
    }

    public func saveLastSearchConditions(_ conditions: [(skillId: SkillId, level: Int)]) throws {
        let rows = conditions.map { ["skillId": Int64($0.skillId), "level": Int64($0.level)] }
        let data = try JSONEncoder().encode(rows)
        try transaction {
            try exec("UPDATE AppState SET lastSearchConditions = ? WHERE id = 1",
                     [.text(String(decoding: data, as: UTF8.self))])
        }
    }

    // MARK: - 起動時処理(仕様5.2)

    private func open() throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            handle = nil
            throw StoreError.cannotOpen(message)
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
        try createSchema()
    }

    private func isCorrupted() throws -> Bool {
        var ok = false
        try query("PRAGMA integrity_check") { stmt in
            if String(cString: sqlite3_column_text(stmt, 0)) == "ok" { ok = true }
        }
        return !ok
    }

    /// user.db を user.db.corrupt.<日時> に退避し、空のDBを再作成(仕様5.2 手順2)
    private func recoverFromCorruption() throws {
        sqlite3_close(handle)
        handle = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let suffix = ".corrupt.\(formatter.string(from: Date()))"
        let fileManager = FileManager.default
        for ext in ["", "-wal", "-shm"] {
            let source = path + ext
            if fileManager.fileExists(atPath: source) {
                try? fileManager.moveItem(atPath: source, toPath: path + suffix + ext)
            }
        }
        try open()
        didRecoverFromCorruption = true
    }

    private func createSchema() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS OwnedCharm (
              id TEXT PRIMARY KEY,
              weaponSlots TEXT NOT NULL,
              armorSlots TEXT NOT NULL,
              rarity INTEGER,
              memo TEXT NOT NULL DEFAULT '',
              createdAt REAL NOT NULL,
              updatedAt REAL NOT NULL
            )
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS OwnedCharmSkill (
              ownedCharmId TEXT NOT NULL REFERENCES OwnedCharm(id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              skillId INTEGER NOT NULL,
              level INTEGER NOT NULL,
              PRIMARY KEY (ownedCharmId, position)
            )
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS AppState (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              schemaVersion INTEGER NOT NULL,
              selectedWeaponId INTEGER,
              lastSearchConditions TEXT,
              customWeapon TEXT,
              searchFilters TEXT
            )
            """)
        try exec("INSERT OR IGNORE INTO AppState (id, schemaVersion) VALUES (1, ?)",
                 [.int(Int64(Self.schemaVersion))])
    }

    private func migrateIfNeeded() throws {
        var version = 0
        try query("SELECT schemaVersion FROM AppState WHERE id = 1") { stmt in
            version = Int(sqlite3_column_int64(stmt, 0))
        }
        guard version < Self.schemaVersion else { return }
        // 移行前にバックアップ(仕様5.2 手順3)
        try? FileManager.default.copyItem(atPath: path, toPath: path + ".bak")
        try transaction {
            if version < 2 {
                // v1→v2: カスタム武器カラム追加(既存カラムならエラーを無視)
                try? exec("ALTER TABLE AppState ADD COLUMN customWeapon TEXT")
            }
            if version < 3 {
                // v2→v3: 固定・除外設定カラム追加
                try? exec("ALTER TABLE AppState ADD COLUMN searchFilters TEXT")
            }
            try exec("UPDATE AppState SET schemaVersion = ?", [.int(Int64(Self.schemaVersion))])
        }
    }

    // MARK: - SQLite低レベル

    enum Value {
        case text(String)
        case int(Int64)
        case real(Double)
        case null
    }

    private func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func exec(_ sql: String, _ values: [Value] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(values, to: stmt)
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func query(_ sql: String, _ values: [Value] = [], _ onRow: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(values, to: stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            onRow(stmt)
        }
    }

    private func bind(_ values: [Value], to stmt: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(stmt, position, text, -1, transient)
            case .int(let number): sqlite3_bind_int64(stmt, position, number)
            case .real(let number): sqlite3_bind_double(stmt, position, number)
            case .null: sqlite3_bind_null(stmt, position)
            }
        }
    }

    static func encodeSlots(_ slots: [Int]) -> String {
        (try? String(decoding: JSONEncoder().encode(slots), as: UTF8.self)) ?? "[]"
    }

    static func decodeSlots(_ json: String) -> [Int] {
        (try? JSONDecoder().decode([Int].self, from: Data(json.utf8))) ?? []
    }
}

extension UserStore: @unchecked Sendable {}
