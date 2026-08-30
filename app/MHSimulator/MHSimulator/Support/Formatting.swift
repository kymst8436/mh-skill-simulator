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
        String(localized: "\(name)Lv\(level)",
               comment: "スキル名+レベルの併記(例: 攻撃Lv3)")
    }

    /// 武器/防具プレフィックス付きの空きスロット要約(例「武③ 防①①」)
    static func emptySlotSummary(weapon: [Int], armor: [Int]) -> String {
        var parts: [String] = []
        if !weapon.isEmpty {
            parts.append(String(localized: "武", comment: "武器スロットの略記プレフィックス") + slotSymbols(weapon))
        }
        if !armor.isEmpty {
            parts.append(String(localized: "防", comment: "防具スロットの略記プレフィックス") + slotSymbols(armor))
        }
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
        let parts = [
            group(weapon, label: String(localized: "武", comment: "武器スロットの略記プレフィックス")),
            group(armor, label: String(localized: "防", comment: "防具スロットの略記プレフィックス")),
        ].compactMap { $0 }
        return parts.isEmpty ? "─" : parts.joined(separator: " / ")
    }

    /// 部位ラベル
    static func pieceLabel(_ kind: ArmorPieceKind) -> String {
        switch kind {
        case .head: String(localized: "頭", comment: "防具部位")
        case .chest: String(localized: "胴", comment: "防具部位")
        case .arms: String(localized: "腕", comment: "防具部位")
        case .waist: String(localized: "腰", comment: "防具部位")
        case .legs: String(localized: "脚", comment: "防具部位")
        }
    }

    /// 武器種ラベル(bundled.dbのkind文字列→表示言語の武器種名)
    static func weaponKindLabel(_ kind: String) -> String {
        switch kind {
        case "great-sword": String(localized: "大剣", comment: "武器種")
        case "long-sword": String(localized: "太刀", comment: "武器種")
        case "sword-shield": String(localized: "片手剣", comment: "武器種")
        case "dual-blades": String(localized: "双剣", comment: "武器種")
        case "hammer": String(localized: "ハンマー", comment: "武器種")
        case "hunting-horn": String(localized: "狩猟笛", comment: "武器種")
        case "lance": String(localized: "ランス", comment: "武器種")
        case "gunlance": String(localized: "ガンランス", comment: "武器種")
        case "switch-axe": String(localized: "スラッシュアックス", comment: "武器種")
        case "charge-blade": String(localized: "チャージアックス", comment: "武器種")
        case "insect-glaive": String(localized: "操虫棍", comment: "武器種")
        case "bow": String(localized: "弓", comment: "武器種")
        case "heavy-bowgun": String(localized: "ヘビィボウガン", comment: "武器種")
        case "light-bowgun": String(localized: "ライトボウガン", comment: "武器種")
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

    /// 護石要求の表示文字列(例「攻撃Lv3 + 防具スロ①」。逆引き候補・ウィッシュリスト共通)
    static func requirementText(_ requirement: CharmRules.Requirement, master: MasterDatabase) -> String {
        var parts = requirement.skills
            .map { (master.skills[$0.key]?.name ?? "?", $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { skillLine($0.0, $0.1) }
        parts += requirement.armorSlots.sorted(by: >).map {
            String(localized: "防具スロ", comment: "護石要求の防具スロット略記") + slotSymbols([$0])
        }
        parts += requirement.weaponSlots.sorted(by: >).map {
            String(localized: "武器スロ", comment: "護石要求の武器スロット略記") + slotSymbols([$0])
        }
        return parts.joined(separator: " + ")
    }

    /// スキル分類ラベル
    static func kindLabel(_ kind: SkillKind) -> String {
        switch kind {
        case .armor: String(localized: "防具", comment: "スキル分類")
        case .weapon: String(localized: "武器", comment: "スキル分類")
        case .set: String(localized: "シリーズ", comment: "スキル分類")
        case .group: String(localized: "グループ", comment: "スキル分類")
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
