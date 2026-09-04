import SwiftUI
import MHSimulatorCore

/// 装備比較①: ベースとなるマイセットを選ぶ(画面設計4.17①)
struct EquipmentCompareView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: EquipmentCompareViewModel
    @Binding var path: [ToolRoute]

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            content
        }
        .mhNavigationTitle(String(localized: "装備比較"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            MHBackButton { dismiss() }
        }
        .task { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().tint(Color.mhAccent)
        } else if let message = viewModel.loadErrorMessage {
            MHEmptyState(
                systemImage: "exclamationmark.triangle",
                title: message,
                actionTitle: String(localized: "再試行")) { viewModel.load() }
        } else if viewModel.savedSets.isEmpty {
            MHEmptyState(
                systemImage: "bookmark",
                title: String(localized: "マイセットはまだありません"),
                message: String(localized: "検索して装備詳細から保存すると、ここで装備を比較できます"))
                .mhEntrance(0)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("ベースとなる装備を選ぶ")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextSecondary)
                        .padding(.horizontal, 16)
                    ForEach(viewModel.savedSets) { item in
                        SavedSetPickRow(item: item, master: viewModel.dependencies.master, isEnabled: true, isSelected: false) {
                            viewModel.select(item, for: .base)
                            path.append(.equipmentCompareResult)
                        }
                    }
                    Text("\(viewModel.savedSets.count)件")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .mhEntrance(0)
        }
    }
}

/// マイセットの選択行(4.15の行と同じ見た目。選択sheetでも使う)
struct SavedSetPickRow: View {
    let item: SavedEquipmentSet
    let master: MasterDatabase
    var isEnabled = true
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MHCard {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.mhTextPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text(MySetListViewModel.dateText(item))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mhTextTertiary)
                        }
                        Text(MySetListViewModel.skillSummary(item, master: master))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mhTextSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mhAccent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.mhTextTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 64)
                .background(isSelected ? Color.mhAccentWash : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// 比較側(またはベースの選び直し)のマイセット選択sheet(画面設計4.17 #12)
struct SavedSetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: EquipmentCompareViewModel
    let side: EquipmentCompareViewModel.Side

    private var title: String {
        side == .base ? String(localized: "ベースとなる装備を選ぶ") : String(localized: "比較する装備を選ぶ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mhBackgroundElevated.ignoresSafeArea()
                if viewModel.savedSets.count <= 1, side == .compare {
                    MHEmptyState(
                        systemImage: "bookmark",
                        title: String(localized: "比較できるマイセットがありません"),
                        message: String(localized: "検索して装備詳細からもう1つ保存すると比較できます"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.savedSets) { item in
                                SavedSetPickRow(
                                    item: item,
                                    master: viewModel.dependencies.master,
                                    isEnabled: viewModel.isSelectable(item, for: side),
                                    isSelected: viewModel.set(for: side)?.id == item.id
                                ) {
                                    viewModel.select(item, for: side)
                                    dismiss()
                                }
                            }
                            if side == .compare {
                                Text("ベースに選んだ装備は選べません")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mhTextTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .mhNavigationTitle(title)
            .toolbar {
                MHToolbarButton(title: String(localized: "閉じる")) { dismiss() }
            }
        }
        .presentationBackground(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
    }
}
