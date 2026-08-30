import Foundation
import MHSimulatorCore

/// カスタム武器設定(仕様3.1 2026-08-24改訂)。
/// TU追加武器(巨撃アーティア等)がデータ未収録の間、スロット構成と
/// シリーズ/グループスキル(各1つ・1部位分として発動数に加算)を手動で仮定する。
nonisolated struct CustomWeaponConfig: Codable, Equatable {
    static let weaponId: Int64 = -1

    var slots: [Int] = [3, 3, 3]      // 各要素0〜3(0=スロットなし)
    var setSkillId: SkillId?
    var groupSkillId: SkillId?

    func makeWeapon() -> Weapon {
        var skills: [SkillId: Int] = [:]
        if let setSkillId { skills[setSkillId] = 1 }
        if let groupSkillId { skills[groupSkillId] = 1 }
        return Weapon(
            id: Self.weaponId, kind: "custom", name: String(localized: "カスタム武器"),
            rarity: 8, slots: slots.filter { $0 > 0 }, skills: skills)
    }

    func encoded() -> String? {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func decode(_ json: String) -> CustomWeaponConfig? {
        try? JSONDecoder().decode(CustomWeaponConfig.self, from: Data(json.utf8))
    }
}
