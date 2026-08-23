import SwiftUI

/// 3タブ構成(画面設計§2)。タブごとに独立したNavigationStackを持つ
struct MainTabView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            NavigationStack {
                SearchConditionPlaceholderView()
                    .mhNavigationTitle("検索条件")
            }
            .tabItem { Label("検索", systemImage: "magnifyingglass") }

            NavigationStack {
                CharmListPlaceholderView()
                    .mhNavigationTitle("護石")
            }
            .tabItem { Label("護石", systemImage: "seal") }

            NavigationStack {
                InfoPlaceholderView()
                    .mhNavigationTitle("情報")
            }
            .tabItem { Label("情報", systemImage: "info.circle") }
        }
    }
}

// Phase 3-2以降で本実装に差し替えるプレースホルダ

struct SearchConditionPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            MHEmptyState(
                systemImage: "magnifyingglass",
                title: "検索条件(実装中)",
                message: "Phase 3-2で実装")
        }
    }
}

struct CharmListPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            MHEmptyState(
                systemImage: "seal",
                title: "護石(実装中)",
                message: "Phase 4-1で実装")
        }
    }
}

struct InfoPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            MHEmptyState(
                systemImage: "info.circle",
                title: "情報(実装中)",
                message: "Phase 5-1で実装")
        }
    }
}
