import SwiftUI

// デザイン規約: Docs/DESIGN.md(狩猟ダーク・ミニマル)。本ファイルが実装の正。
// 値の変更はDESIGN.md改訂とセットで行う(§10)。

extension Color {
    init(mhHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    static let mhBackground = Color(mhHex: 0x14120D)
    static let mhBackgroundElevated = Color(mhHex: 0x191712)
    static let mhSurface = Color(mhHex: 0x1E1B14)
    static let mhSurfaceSubtle = Color(mhHex: 0x24211A)
    static let mhHairline = Color(mhHex: 0x3A342A)
    static let mhHairlineFaint = Color(mhHex: 0x2A2620)
    static let mhTextPrimary = Color(mhHex: 0xEDE6D4)
    static let mhTextSecondary = Color(mhHex: 0xA89F87)
    static let mhTextTertiary = Color(mhHex: 0x6F675A)
    static let mhAccent = Color(mhHex: 0xD9A036)
    static let mhAccentSoft = Color(mhHex: 0xE3C87F)
    static let mhAccentDim = Color(mhHex: 0x8A6F30)
    static let mhOnAccent = Color(mhHex: 0x1A1204)
    static let mhAccentWash = Color(mhHex: 0xD9A036).opacity(0.10)
    static let mhDestructive = Color(mhHex: 0xC25B4A)
    static let mhTitleGold = Color(mhHex: 0xE8D9A8)

    static func mhRarity(_ rarity: Int) -> Color {
        switch rarity {
        case ...1: Color(mhHex: 0x8F8A7E)
        case 2: Color(mhHex: 0xA9A395)
        case 3: Color(mhHex: 0x6FA36B)
        case 4: Color(mhHex: 0x5FA898)
        case 5: Color(mhHex: 0x5B8FC2)
        case 6: Color(mhHex: 0x9678C8)
        case 7: Color(mhHex: 0xC46A5A)
        default: Color(mhHex: 0xD9A036)  // R8
        }
    }
}

enum MHFont {
    static let screenTitle = Font.custom("HiraMinProN-W6", size: 17, relativeTo: .headline)
    static let statNumber = Font.custom("HiraMinProN-W6", size: 24, relativeTo: .title2)
    static let button = Font.custom("HiraMinProN-W6", size: 17, relativeTo: .headline)
}

enum MHTheme {
    /// UIKit外観の一括設定(タブバー・ナビバー)。App起動時に1回呼ぶ
    static func configureAppearance() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Color.mhBackgroundElevated)
        tabBar.shadowColor = UIColor(Color.mhHairline)
        for item in [tabBar.stackedLayoutAppearance, tabBar.inlineLayoutAppearance, tabBar.compactInlineLayoutAppearance] {
            item.selected.iconColor = UIColor(Color.mhAccent)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.mhAccent)]
            item.normal.iconColor = UIColor(Color.mhTextTertiary)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(Color.mhTextTertiary)]
        }
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = UIColor(Color.mhBackgroundElevated)
        navBar.shadowColor = UIColor(Color.mhHairline)
        // タイトル文字はToolbarItem(placement: .principal)のMHScreenTitleで描く。
        // フォールバック(標準タイトルが出る画面)向けの既定も設定しておく
        navBar.titleTextAttributes = [
            .foregroundColor: UIColor(Color.mhTitleGold),
            .font: UIFont(name: "HiraMinProN-W6", size: 17) ?? .boldSystemFont(ofSize: 17),
            .kern: 1.5,
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().tintColor = UIColor(Color.mhAccent)
    }
}
