import Foundation
import MHSimulatorCore

/// 表記規約(画面設計§6): スロット記号・スキル表記・レア度表記
nonisolated enum MHFormat {
    /// サイズを①②③で大きい順に。空は「─」
    static func slotSymbols(_ slots: [Int]) -> String {
        guard !slots.isEmpty else { return "─" }
        let symbols = ["", "①", "②", "③"]
        return slots.sorted(by: >).map { symbols[min($0, 3)] }.joined()
    }

    /// 「攻撃Lv3」形式
    static func skillLine(_ name: String, _ level: Int) -> String {
        "\(name)Lv\(level)"
    }

    /// 武器/防具プレフィックス付きの空きスロット要約(例「武③ 防①①」)
    static func emptySlotSummary(weapon: [Int], armor: [Int]) -> String {
        var parts: [String] = []
        if !weapon.isEmpty { parts.append("武" + slotSymbols(weapon)) }
        if !armor.isEmpty { parts.append("防" + slotSymbols(armor)) }
        return parts.isEmpty ? "─" : parts.joined(separator: " ")
    }

    /// 空きスロットのサイズ×個数サマリ(結果カード用。例「武 ③① / 防 ③×6 ①×2」)
    static func slotCountSummary(weapon: [Int], armor: [Int]) -> String {
        func group(_ slots: [Int], label: String) -> String? {
            guard !slots.isEmpty else { return nil }
            let counts = Dictionary(grouping: slots, by: { $0 }).mapValues(\.count)
            let parts = counts.keys.sorted(by: >).map { size in
                let symbol = slotSymbols([size])
                let count = counts[size]!
                return count == 1 ? symbol : "\(symbol)×\(count)"
            }
            return label + " " + parts.joined(separator: " ")
        }
        let parts = [group(weapon, label: "武"), group(armor, label: "防")].compactMap { $0 }
        return parts.isEmpty ? "─" : parts.joined(separator: " / ")
    }

    /// 部位ラベル
    static func pieceLabel(_ kind: ArmorPieceKind) -> String {
        switch kind {
        case .head: "頭"
        case .chest: "胴"
        case .arms: "腕"
        case .waist: "腰"
        case .legs: "脚"
        }
    }

    /// 武器種ラベル(bundled.dbのkind文字列→日本語)
    static func weaponKindLabel(_ kind: String) -> String {
        switch kind {
        case "great-sword": "大剣"
        case "long-sword": "太刀"
        case "sword-shield": "片手剣"
        case "dual-blades": "双剣"
        case "hammer": "ハンマー"
        case "hunting-horn": "狩猟笛"
        case "lance": "ランス"
        case "gunlance": "ガンランス"
        case "switch-axe": "スラッシュアックス"
        case "charge-blade": "チャージアックス"
        case "insect-glaive": "操虫棍"
        case "bow": "弓"
        case "heavy-bowgun": "ヘビィボウガン"
        case "light-bowgun": "ライトボウガン"
        default: kind
        }
    }

    /// 全武器種(表示順)
    static let weaponKinds: [String] = [
        "great-sword", "long-sword", "sword-shield", "dual-blades",
        "hammer", "hunting-horn", "lance", "gunlance",
        "switch-axe", "charge-blade", "insect-glaive",
        "bow", "heavy-bowgun", "light-bowgun",
    ]

    /// 武器種アイコンのアセット名(未収録の武器種=カスタム武器はnil)
    static func weaponIconName(_ kind: String) -> String? {
        weaponKinds.contains(kind) ? "weapon_\(kind)" : nil
    }

    /// 防具部位アイコンのアセット名
    static func pieceIconName(_ kind: ArmorPieceKind) -> String {
        switch kind {
        case .head: "piece_head"
        case .chest: "piece_chest"
        case .arms: "piece_arms"
        case .waist: "piece_waist"
        case .legs: "piece_legs"
        }
    }

    /// 護石アイコンのアセット名
    static let charmIconName = "icon_charm"

    /// スキル分類ラベル
    static func kindLabel(_ kind: SkillKind) -> String {
        switch kind {
        case .armor: "防具"
        case .weapon: "武器"
        case .set: "シリーズ"
        case .group: "グループ"
        }
    }
}

nonisolated extension String {
    /// ひらがな/カタカナを同一視した部分一致(画面設計4.2)
    func mhContains(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let normalizedSelf = applyingTransform(.hiraganaToKatakana, reverse: false) ?? self
        let normalizedQuery = query.applyingTransform(.hiraganaToKatakana, reverse: false) ?? query
        return normalizedSelf.localizedCaseInsensitiveContains(normalizedQuery)
    }
}
