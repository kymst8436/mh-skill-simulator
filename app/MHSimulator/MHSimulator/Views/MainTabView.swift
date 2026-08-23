import SwiftUI

/// 3タブ構成(画面設計§2)。タブごとに独立したNavigationStackを持つ
struct MainTabView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            SearchConditionView(dependencies: dependencies)
                .tabItem { Label("検索", systemImage: "magnifyingglass") }

            CharmListView(dependencies: dependencies)
                .tabItem { Label("護石", systemImage: "seal") }

            NavigationStack {
                InfoPlaceholderView()
                    .mhNavigationTitle("情報")
            }
            .tabItem { Label("情報", systemImage: "info.circle") }
        }
    }
}

// Phase 5で本実装に差し替えるプレースホルダ

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
