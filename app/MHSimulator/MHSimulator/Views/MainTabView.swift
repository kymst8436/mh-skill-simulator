import SwiftUI

/// 5タブ構成(画面設計§2。2026-09-04: ツールタブ追加)。タブバーは自作MHTabBar(DESIGN.md §4)
struct MainTabView: View {
    let dependencies: AppDependencies
    @State private var selection: MHTab = .search

    var body: some View {
        ZStack {
            tabs
            // 初回起動時コーチマーク(ナビバー・タブバーごと覆う。CoachMarkCenter参照)
            CoachMarkOverlay()
        }
    }

    private var tabs: some View {
        // TabViewの下に自作タブバーを並べる(タブ画面のコンテンツ領域をタブバー上端までに制限)
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                SearchConditionView(dependencies: dependencies)
                    .tag(MHTab.search)
                    .toolbar(.hidden, for: .tabBar)

                MySetListView(dependencies: dependencies)
                    .tag(MHTab.mySets)
                    .toolbar(.hidden, for: .tabBar)

                CharmListView(dependencies: dependencies)
                    .tag(MHTab.charms)
                    .toolbar(.hidden, for: .tabBar)

                ToolListView(dependencies: dependencies)
                    .tag(MHTab.tools)
                    .toolbar(.hidden, for: .tabBar)

                InfoView(dependencies: dependencies)
                    .tag(MHTab.info)
                    .toolbar(.hidden, for: .tabBar)
            }
            MHTabBar(selection: $selection)
        }
    }
}
