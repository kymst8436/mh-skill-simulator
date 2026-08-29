import SwiftUI
import MHSimulatorCore

/// マイセットタブの遷移先
nonisolated enum MySetRoute: Hashable {
    case detail(SavedSetItem)
}

/// SavedEquipmentSetをナビゲーション引数にするためのIdラッパ(EquipmentSetItemと同じ流儀)
nonisolated struct SavedSetItem: Hashable, Identifiable {
    let id = UUID()
    let saved: SavedEquipmentSet

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// マイセットタブ: 検索結果から保存した装備セットの一覧・確認・削除(画面設計4.15 2026-08-29追加)
struct MySetListView: View {
    let dependencies: AppDependencies
    @State private var viewModel: MySetListViewModel
    @State private var path: [MySetRoute] = []
    @State private var pendingDelete: SavedEquipmentSet?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: MySetListViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                content
            }
            .mhNavigationTitle("マイセット")
            .task { viewModel.load() }
            .navigationDestination(for: MySetRoute.self) { route in
                switch route {
                case .detail(let item):
                    // 保存時の条件スキルで★条件表示を再現する(画面設計4.15)
                    EquipmentDetailView(
                        dependencies: dependencies,
                        item: EquipmentSetItem(set: item.saved.set),
                        condition: SearchCondition(requiredSkills: item.saved.conditionSkills),
                        allowsSave: false)
                }
            }
            .confirmationDialog(
                "このマイセットを削除しますか?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let item = pendingDelete { viewModel.delete(item) }
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

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().tint(Color.mhAccent)
        } else if let message = viewModel.loadErrorMessage {
            MHEmptyState(
                systemImage: "exclamationmark.triangle",
                title: message,
                actionTitle: "再試行") { viewModel.load() }
        } else if viewModel.savedSets.isEmpty {
            MHEmptyState(
                systemImage: "bookmark",
                title: "マイセットはまだありません",
                message: "検索結果からマイセットを追加できます")
                .mhEntrance(0)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.savedSets) { item in
                        setRow(item)
                    }
                    Text("\(viewModel.savedSets.count)件")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextTertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .mhEntrance(0)
        }
    }

    private func setRow(_ item: SavedEquipmentSet) -> some View {
        Button {
            path.append(.detail(SavedSetItem(saved: item)))
        } label: {
            MHCard {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.mhTextPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text(viewModel.dateText(item))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mhTextTertiary)
                        }
                        Text(viewModel.skillSummary(item))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mhTextSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
            }
        }
        .contextMenu {
            Button("削除", role: .destructive) { pendingDelete = item }
        }
    }
}
