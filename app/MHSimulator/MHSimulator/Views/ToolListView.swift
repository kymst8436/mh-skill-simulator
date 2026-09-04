import SwiftUI
import MHSimulatorCore

/// ツールタブ内のナビゲーション
nonisolated enum ToolRoute: Hashable {
    case equipmentCompare        // 装備比較①: マイセット選択(画面設計4.17)
    case equipmentCompareResult  // 装備比較②: 比較画面
}

/// ツール一覧の定義(画面設計4.16)。ツールを増やすときはここに追加する
enum ToolCatalog: CaseIterable, Identifiable {
    case equipmentCompare

    var id: Self { self }

    var title: String {
        switch self {
        case .equipmentCompare: String(localized: "装備比較")
        }
    }

    var summary: String {
        switch self {
        case .equipmentCompare: String(localized: "マイセットの装備構成から物理攻撃力の期待値を比較します。攻撃装備と会心装備の比較に便利です。")
        }
    }

    var systemImage: String {
        switch self {
        case .equipmentCompare: "arrow.left.arrow.right"
        }
    }

    var route: ToolRoute {
        switch self {
        case .equipmentCompare: .equipmentCompare
        }
    }
}

/// ツールタブ(画面設計4.16)。ワイルズ向けの便利機能の入口
struct ToolListView: View {
    let dependencies: AppDependencies
    @State private var path: [ToolRoute] = []
    @State private var compareViewModel: EquipmentCompareViewModel
    @State private var showsAdFreeSheet = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _compareViewModel = State(initialValue: EquipmentCompareViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MHSectionHeader(title: String(localized: "ダメージ"))
                            .padding(.top, 20)
                        MHCard {
                            VStack(spacing: 0) {
                                ForEach(ToolCatalog.allCases) { tool in
                                    toolRow(tool)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        .mhEntrance(0)

                        Text("ツールは今後追加していきます")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mhTextTertiary)
                            .padding(.horizontal, 32)
                            .padding(.top, 20)
                            .mhEntrance(1)
                    }
                    .padding(.bottom, 24)
                }
            }
            .mhNavigationTitle(String(localized: "ツール"))
            .safeAreaInset(edge: .top, spacing: 0) { AdBannerView(adUnitId: AdConfig.toolsBannerUnitId) }
            .toolbar {
                AdFreeToolbarButton { showsAdFreeSheet = true }
            }
            .sheet(isPresented: $showsAdFreeSheet) {
                AdFreeSheetView()
            }
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .equipmentCompare:
                    EquipmentCompareView(viewModel: compareViewModel, path: $path)
                case .equipmentCompareResult:
                    EquipmentCompareResultView(viewModel: compareViewModel)
                }
            }
        }
    }

    private func toolRow(_ tool: ToolCatalog) -> some View {
        Button {
            path.append(tool.route)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.mhAccent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mhTextPrimary)
                    Text(tool.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mhTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
