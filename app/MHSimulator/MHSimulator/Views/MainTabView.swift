import SwiftUI

/// 3タブ構成(画面設計§2)。タブバーは自作MHTabBar(DESIGN.md §4)
struct MainTabView: View {
    let dependencies: AppDependencies
    @State private var selection: MHTab = .search

    var body: some View {
        TabView(selection: $selection) {
            SearchConditionView(dependencies: dependencies)
                .tag(MHTab.search)
                .toolbar(.hidden, for: .tabBar)

            CharmListView(dependencies: dependencies)
                .tag(MHTab.charms)
                .toolbar(.hidden, for: .tabBar)

            InfoView(dependencies: dependencies)
                .tag(MHTab.info)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MHTabBar(selection: $selection)
        }
    }
}
