import SwiftUI
import MHSimulatorCore

/// ウィッシュリストへの手動追加sheet(画面設計4.11。2026-08-25追加)。
/// スキル選択は護石入力と同じ規則ベース補助(CharmEntryViewModel)を共用する。
/// スロット・レア度・メモは持たない(要求はスキルのみ。最小レア度は自動表示)
struct WishlistEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let dependencies: AppDependencies
    /// 追加完了時(親が一覧を再読込する)
    let onSaved: () -> Void
    @State private var viewModel: CharmEntryViewModel
    @State private var saveErrorMessage: String?

    init(dependencies: AppDependencies, onSaved: @escaping () -> Void) {
        self.dependencies = dependencies
        self.onSaved = onSaved
        _viewModel = State(initialValue: CharmEntryViewModel(dependencies: dependencies, target: .new))
    }

    private var selectedSkills: [CharmRules.GroupEntry] {
        [viewModel.skill1, viewModel.skill2, viewModel.skill3].compactMap { $0 }
    }

    private var requirement: CharmRules.Requirement {
        CharmRules.Requirement(
            skills: Dictionary(selectedSkills.map { ($0.skillId, $0.level) }) { max($0, $1) })
    }

    private var minimumRarity: Int? {
        guard !selectedSkills.isEmpty else { return nil }
        return dependencies.master.charmRules.minimumRarity(satisfying: requirement)
    }

    private var canAdd: Bool { !selectedSkills.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                MHSectionHeader(title: String(localized: "欲しいスキル"))
                                    .padding(.top, 16)
                                MHCard {
                                    VStack(spacing: 0) {
                                        skillRow(position: 0, label: String(localized: "スキル1"), entry: viewModel.skill1, enabled: true, allowsNone: false)
                                        separator
                                        skillRow(position: 1, label: String(localized: "スキル2"), entry: viewModel.skill2, enabled: viewModel.skill1 != nil, allowsNone: true)
                                        separator
                                        skillRow(position: 2, label: String(localized: "スキル3"), entry: viewModel.skill3, enabled: viewModel.skill2 != nil, allowsNone: true)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                note(String(localized: "抽選規則上あり得る組み合わせだけが選べます"))
                            }
                            .mhEntrance(0)

                            if let rarity = minimumRarity {
                                Group {
                                    MHSectionHeader(title: String(localized: "出現レア度"))
                                        .padding(.top, 20)
                                    MHCard {
                                        HStack(spacing: 8) {
                                            RarityBadge(rarity: rarity)
                                            Text("以上の護石で出現します")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.mhTextSecondary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(minHeight: 44)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 6)
                                }
                                .mhEntrance(1)
                            }

                            if let message = saveErrorMessage {
                                Text(message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.mhDestructive)
                                    .padding(.horizontal, 32)
                                    .padding(.top, 12)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    addButtonBar
                        .mhEntrance(2)
                }
            }
            .mhNavigationTitle(String(localized: "ウィッシュリストに追加"))
            .toolbar {
                MHToolbarButton(title: String(localized: "キャンセル"), placement: .topBarLeading) { dismiss() }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var addButtonBar: some View {
        MHPrimaryButton(title: String(localized: "追加する"), isEnabled: canAdd) {
            let item = WishlistItem(skills: selectedSkills)
            do {
                try dependencies.userStore.insertWishlistItem(item)
                onSaved()
                dismiss()
            } catch {
                saveErrorMessage = String(localized: "保存できませんでした。端末の空き容量をご確認ください")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mhBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairlineFaint).frame(height: 1)
        }
    }

    /// 護石入力と同じ規則ベースのスキル選択行(CharmSkillCandidateViewを共用)
    private func skillRow(position: Int, label: String, entry: CharmRules.GroupEntry?, enabled: Bool, allowsNone: Bool) -> some View {
        NavigationLink {
            CharmSkillCandidateView(
                viewModel: viewModel, position: position, title: label, allowsNone: allowsNone)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                    .fixedSize()
                    .frame(minWidth: 52, alignment: .leading)
                Text(viewModel.entryLabel(entry))
                    .font(.system(size: 16))
                    .foregroundStyle(entry == nil ? Color.mhTextTertiary : Color.mhTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.mhTextTertiary)
            .padding(.horizontal, 32)
            .padding(.top, 8)
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }
}
