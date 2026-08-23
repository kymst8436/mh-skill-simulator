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

            InfoView(dependencies: dependencies)
                .tabItem { Label("情報", systemImage: "info.circle") }
        }
    }
}

