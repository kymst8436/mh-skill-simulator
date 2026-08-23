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
