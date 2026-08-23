import Foundation
import XCTest
@testable import MHSimulatorCore

/// テスト共通: bundled.db をリポジトリの data/generated/ から読み込む。
/// 生成されていない場合は tools/convert/convert.py の実行が必要。
enum TestSupport {
    static let repoRoot: URL = {
        // .../app/MHSimulatorCore/Tests/MHSimulatorCoreTests/TestSupport.swift → リポジトリルート
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // → MHSimulatorCoreTests/
            .deletingLastPathComponent()  // → Tests/
            .deletingLastPathComponent()  // → MHSimulatorCore/
            .deletingLastPathComponent()  // → app/
            .deletingLastPathComponent()  // → リポジトリルート
    }()

    static let bundledDbPath = repoRoot
        .appendingPathComponent("data/generated/bundled.db").path
    static let enumeratedDbPath = repoRoot
        .appendingPathComponent("data/generated/enumerated.db").path

    static let master: MasterDatabase = {
        do {
            return try MasterDatabase(path: bundledDbPath)
        } catch {
            fatalError("bundled.dbを読み込めません(tools/convert/convert.pyを実行してください): \(error)")
        }
    }()

    /// スロットもスキルも持たない実在武器(「武器の寄与ゼロ」を固定するテスト用)
    static var slotlessWeapon: Weapon {
        master.weapons.first { $0.slots.isEmpty && $0.skills.isEmpty }!
    }

    static func skill(named name: String) -> Skill {
        guard let skill = master.skills.values.first(where: { $0.name == name }) else {
            fatalError("スキルが見つかりません: \(name)")
        }
        return skill
    }
}
