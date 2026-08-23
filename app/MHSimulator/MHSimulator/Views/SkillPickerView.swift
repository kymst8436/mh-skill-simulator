import SwiftUI
import MHSimulatorCore

/// スキル選択sheet(画面設計4.2)。タップで追加/削除のトグル、開いたまま連続追加できる
struct SkillPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let conditionViewModel: SearchConditionViewModel
    @State private var viewModel: SkillPickerViewModel

    init(conditionViewModel: SearchConditionViewModel) {
        self.conditionViewModel = conditionViewModel
        _viewModel = State(initialValue: SkillPickerViewModel(
            master: conditionViewModel.dependencies.master))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            kindFilterBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Rectangle().fill(Color.mhHairline).frame(height: 1)
            skillList
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Button("キャンセル") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(Color.mhAccent)
                .frame(width: 84, alignment: .leading)
            Spacer()
            Text("スキルを選択")
                .font(MHFont.screenTitle)
                .tracking(1.5)
                .foregroundStyle(Color.mhTitleGold)
            Spacer()
            Color.clear.frame(width: 84, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
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
        let isSelected = conditionViewModel.selectedSkillIds.contains(skill.id)
        return Button {
            conditionViewModel.toggleSkill(skill)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.mhAccent)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 18, height: 18)
                Text(skill.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
                Text(MHFormat.kindLabel(skill.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mhTextSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
                Text("最大Lv\(skill.maxLevel)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(isSelected ? Color.mhAccentWash : .clear)
        }
    }
}
