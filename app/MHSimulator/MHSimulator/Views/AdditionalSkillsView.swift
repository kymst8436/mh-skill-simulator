import SwiftUI
import MHSimulatorCore

/// 追加スキルsheet(画面設計4.12)。条件に追加しても組めるスキルを一覧し、タップで条件に追加して再検索
struct AdditionalSkillsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AdditionalSkillsViewModel
    @State private var detailSkill: Skill?

    init(viewModel: AdditionalSkillsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .mhEntrance(0)
            content
                .mhEntrance(1)
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .sheet(item: $detailSkill) { skill in
            SkillDetailView(master: viewModel.master, skill: skill)
        }
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 84, height: 1)
            Spacer()
            Text("追加できるスキル")
                .font(MHFont.screenTitle)
                .tracking(1.5)
                .foregroundStyle(Color.mhTitleGold)
            Spacer()
            Button("閉じる") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(Color.mhAccent)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .judging:
            judgingProgress
                .frame(maxHeight: .infinity)
        case .list:
            entryList
        case .empty:
            MHEmptyState(
                systemImage: "checkmark.seal",
                title: String(localized: "追加できるスキルはありません"),
                message: String(localized: "現在の条件はスキル枠を使い切っています。条件を減らすと余裕が生まれます"))
                .frame(maxHeight: .infinity)
        case .failed:
            MHEmptyState(
                systemImage: "exclamationmark.triangle",
                title: String(localized: "判定できませんでした"),
                actionTitle: String(localized: "再試行")) { viewModel.retry() }
                .frame(maxHeight: .infinity)
        }
    }

    private var judgingProgress: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.mhAccent)
            Text("追加できるスキルを判定中…")
                .font(.system(size: 13))
                .foregroundStyle(Color.mhTextSecondary)
            if viewModel.targetCount > 0 {
                Text("\(viewModel.determinedCount)/\(viewModel.targetCount) スキル")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mhTextTertiary)
            }
        }
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("\(viewModel.entries.count)件のスキルを追加できます")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextSecondary)
                    .padding(.horizontal, 16)
                Text("タップすると条件に追加して再検索します")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mhTextTertiary)
                    .padding(.horizontal, 16)
                ForEach(viewModel.entries, id: \.self) { entry in
                    entryRow(entry)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func entryRow(_ entry: AdditionalSkillFinder.Entry) -> some View {
        Button {
            viewModel.select(entry)
            dismiss()
        } label: {
            MHCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.skillLabel(entry.skillId))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Text("+Lv\(entry.maxAddableLevel)まで")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mhAccent)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .mhSkillDetailContextMenu { detailSkill = viewModel.master.skills[entry.skillId] }
    }
}
