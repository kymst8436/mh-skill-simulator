import SwiftUI
import MHSimulatorCore

/// スキル選択sheet(画面設計4.2)。タップで追加/削除のトグル、開いたまま連続追加できる
struct SkillPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let conditionViewModel: SearchConditionViewModel
    @State private var viewModel: SkillPickerViewModel
    @State private var detailSkill: Skill?

    init(conditionViewModel: SearchConditionViewModel) {
        self.conditionViewModel = conditionViewModel
        _viewModel = State(initialValue: SkillPickerViewModel(
            master: conditionViewModel.dependencies.master))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .mhEntrance(0)
            Group {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                if !conditionViewModel.conditions.isEmpty {
                    selectedSummary
                        .padding(.bottom, 10)
                }
                kindFilterBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            .mhEntrance(1)
            Rectangle().fill(Color.mhHairline).frame(height: 1)
            skillList
                .mhEntrance(2)
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
        .sheet(item: $detailSkill) { skill in
            SkillDetailView(master: conditionViewModel.dependencies.master, skill: skill)
        }
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 84, height: 1)
            Spacer()
            Text("スキルを選択")
                .font(MHFont.screenTitle)
                .tracking(1.5)
                .foregroundStyle(Color.mhTitleGold)
            Spacer()
            // 選択は即時反映(ライブ同期)なのでキャンセルは置かない(2026-08-24改訂)
            Button("OK") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mhAccent)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    /// 選択中スキルの1行サマリ(見切れは横スクロール。2026-08-24改訂)
    private var selectedSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(conditionViewModel.conditions
                .map { "\($0.skill.name)Lv\($0.level)" }
                .joined(separator: ", "))
                .font(.system(size: 13))
                .foregroundStyle(Color.mhAccentSoft)
                .lineLimit(1)
                .padding(.horizontal, 16)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextTertiary)
            TextField("", text: $viewModel.searchText,
                      prompt: Text("スキル名で検索").foregroundStyle(Color.mhTextTertiary))
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextPrimary)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
    }

    private var kindFilterBar: some View {
        HStack(spacing: 2) {
            ForEach(SkillPickerViewModel.KindFilter.allCases) { filter in
                let isSelected = viewModel.kindFilter == filter
                Button {
                    viewModel.kindFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.mhTextPrimary : Color.mhTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(isSelected ? Color.mhHairline : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .padding(2)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var skillList: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            if viewModel.visibleSkills.isEmpty {
                MHEmptyState(
                    systemImage: "magnifyingglass",
                    title: "「\(viewModel.searchText)」に一致するスキルはありません")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.visibleSkills, id: \.id) { skill in
                            skillRow(skill)
                            Rectangle()
                                .fill(Color.mhHairlineFaint)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        let selectedRow = conditionViewModel.conditions.first { $0.id == skill.id }
        return Button {
            conditionViewModel.toggleSkill(skill)
        } label: {
            HStack(spacing: 10) {
                Text(MHFormat.kindLabel(skill.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mhTextSecondary)
                    .padding(.vertical, 2)
                    .frame(width: 52)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
                Text(skill.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
                if let row = selectedRow {
                    Text("Lv\(row.level)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mhAccent)
                    MHStepper(
                        canDecrement: row.level > 1,
                        canIncrement: row.level < skill.maxLevel,
                        size: 26,
                        onDecrement: { conditionViewModel.setLevel(skill.id, row.level - 1) },
                        onIncrement: { conditionViewModel.setLevel(skill.id, row.level + 1) })
                } else {
                    Text("最大Lv\(skill.maxLevel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(selectedRow != nil ? Color.mhAccentWash : .clear)
        }
        .mhSkillDetailContextMenu { detailSkill = skill }
    }
}
