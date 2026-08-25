import SwiftUI
import MHSimulatorCore

/// 護石タブ: 所持護石の一覧・追加・編集・削除(画面設計4.6)
struct CharmListView: View {
    /// 護石タブの表示切替(2026-08-25追加)
    enum Tab: String, CaseIterable {
        case owned = "所持護石"
        case wishlist = "ウィッシュリスト"
    }

    let dependencies: AppDependencies
    @State private var viewModel: CharmListViewModel
    @State private var entryTarget: CharmEntryTarget?
    @State private var pendingDelete: OwnedCharm?
    @State private var tab: Tab = .owned
    @State private var showsWishlistEntry = false
    /// ウィッシュリスト行タップ→護石入力プリセット(保存でリストから消す)
    @State private var wishlistEntryTarget: WishlistItem?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: CharmListViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    tabBar
                        .mhEntrance(0)
                    // 空状態・読込中でもタブ位置が動かないよう、コンテンツ側が残り領域を占有する
                    Group {
                        switch tab {
                        case .owned: content
                        case .wishlist: wishlistContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .mhNavigationTitle("護石")
            .safeAreaInset(edge: .top, spacing: 0) { AdBannerView(adUnitId: AdConfig.charmBannerUnitId) }
            .toolbar {
                MHToolbarButton(title: "+ 追加") {
                    switch tab {
                    case .owned: entryTarget = .new
                    case .wishlist: showsWishlistEntry = true
                    }
                }
            }
            .task { viewModel.load() }
            .sheet(item: $entryTarget) { target in
                CharmEntryView(dependencies: dependencies, target: target) {
                    viewModel.load()
                }
            }
            .sheet(isPresented: $showsWishlistEntry) {
                WishlistEntryView(dependencies: dependencies) {
                    viewModel.load()
                }
            }
            .sheet(item: $wishlistEntryTarget) { item in
                // 入手した護石を登録→ウィッシュリストから自動で外す
                CharmEntryView(dependencies: dependencies, target: .preset(item.requirement)) {
                    viewModel.deleteWishlistItem(item)
                    viewModel.load()
                }
            }
            .confirmationDialog(
                "この護石を削除しますか?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let charm = pendingDelete { viewModel.delete(charm) }
                    pendingDelete = nil
                }
                Button("キャンセル", role: .cancel) { pendingDelete = nil }
            }
            .alert(
                viewModel.deleteErrorMessage ?? "",
                isPresented: Binding(
                    get: { viewModel.deleteErrorMessage != nil },
                    set: { if !$0 { viewModel.deleteErrorMessage = nil } })
            ) {
                Button("OK") {}
            }
        }
    }

    /// 所持/ウィッシュリストの切替(下線式タブ。2026-08-26改訂)
    private var tabBar: some View {
        MHUnderlineTabs(
            tabs: Tab.allCases.map { (tab: $0, label: $0.rawValue) },
            selection: $tab)
    }

    // MARK: - ウィッシュリスト(2026-08-25追加)

    @ViewBuilder
    private var wishlistContent: some View {
        if viewModel.wishlist.isEmpty {
            MHEmptyState(
                systemImage: "sparkles",
                title: "ウィッシュリストは空です",
                message: "[+追加] で欲しい護石を登録できます。検索結果の護石候補からもワンタップで追加できます",
                actionTitle: "追加する") { showsWishlistEntry = true }
                .mhEntrance(1)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.wishlist) { item in
                        wishlistRow(item)
                    }
                    Text("入手したらタップで所持護石として登録できます")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mhTextTertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .mhEntrance(1)
        }
    }

    private func wishlistRow(_ item: WishlistItem) -> some View {
        Button {
            wishlistEntryTarget = item
        } label: {
            MHCard {
                HStack(spacing: 10) {
                    Image(MHFormat.charmIconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text(viewModel.requirementText(item))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if let rarity = viewModel.minimumRarity(item) {
                        RarityBadge(rarity: rarity)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
            }
        }
        .contextMenu {
            Button("削除", role: .destructive) { viewModel.deleteWishlistItem(item) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().tint(Color.mhAccent)
        } else if let message = viewModel.loadErrorMessage {
            MHEmptyState(
                systemImage: "exclamationmark.triangle",
                title: message,
                actionTitle: "再試行") { viewModel.load() }
        } else if viewModel.charms.isEmpty {
            MHEmptyState(
                systemImage: "seal",
                title: "護石がまだ登録されていません",
                message: "[+追加] から所持している鑑定護石を登録してください",
                actionTitle: "追加する") { entryTarget = .new }
                .mhEntrance(1)
        } else {
            charmList
                .mhEntrance(1)
        }
    }

    private var charmList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.charms) { charm in
                    charmRow(charm)
                }
                Text("\(viewModel.charms.count)個")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func charmRow(_ charm: OwnedCharm) -> some View {
        Button {
            entryTarget = .edit(charm)
        } label: {
            MHCard {
                HStack(spacing: 10) {
                    Image(MHFormat.charmIconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text(viewModel.displayName(charm))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if let rarity = charm.rarity {
                        RarityBadge(rarity: rarity)
                    }
                    Text(viewModel.slotText(charm))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhTextSecondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
            }
        }
        .contextMenu {
            Button("削除", role: .destructive) { pendingDelete = charm }
        }
        .swipeActions {
            Button("削除", role: .destructive) { pendingDelete = charm }
        }
    }
}

/// 護石入力sheetの起動モード
enum CharmEntryTarget: Identifiable {
    case new
    case edit(OwnedCharm)
    case preset(CharmRules.Requirement)  // 逆引き候補からのプリセット(画面設計4.7)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let charm): charm.id.uuidString
        case .preset: "preset"
        }
    }
}
