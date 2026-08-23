import SwiftUI
import MHSimulatorCore

/// 検索結果(画面設計4.4)。1件以上=カードリスト / 0件=同画面内で逆引き提示
struct SearchResultsView: View {
    let dependencies: AppDependencies
    let conditionViewModel: SearchConditionViewModel
    @Binding var path: [SearchRoute]
    @State private var viewModel: SearchResultsViewModel
    @State private var entryTarget: CharmEntryTarget?

    init(dependencies: AppDependencies, conditionViewModel: SearchConditionViewModel, path: Binding<[SearchRoute]>) {
        self.dependencies = dependencies
        self.conditionViewModel = conditionViewModel
        _path = path
        _viewModel = State(initialValue: SearchResultsViewModel(
            dependencies: dependencies, conditionViewModel: conditionViewModel))
    }

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            content
        }
        .mhNavigationTitle("検索結果")
        .navigationBarBackButtonHidden(true)
        .toolbar { MHBackButton { path.removeLast() } }
        .safeAreaInset(edge: .top, spacing: 0) { AdBannerView(adUnitId: AdConfig.searchBannerUnitId) }
        .task { viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .sheet(item: $entryTarget) { target in
            // 逆引き候補→護石入力プリセット(画面設計4.7)。保存後は自動で再検索
            CharmEntryView(dependencies: dependencies, target: target) {
                viewModel.reloadAndRetry()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .searching:
            VStack(spacing: 12) {
                ProgressView().tint(Color.mhAccent)
                Text("検索中…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextSecondary)
            }
        case .results(let result):
            resultList(result)
        case .reverseSearching:
            VStack(spacing: 0) {
                notFoundHeader
                VStack(spacing: 12) {
                    ProgressView().tint(Color.mhAccent)
                    Text("狙える護石を探しています…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextSecondary)
                }
                .padding(.top, 12)
                Spacer()
            }
        case .reverse(let outcome):
            reverseContent(outcome)
        case .failed:
            MHEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "検索できませんでした",
                message: "条件を減らしてお試しください",
                actionTitle: "再試行") { viewModel.retry() }
        }
    }

    // MARK: - 結果あり

    private func resultList(_ result: SearchResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.truncated
                         ? "\(result.sets.count)件(上限で打ち切り。条件を絞ると精度が上がります)"
                         : "\(result.sets.count)件")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextSecondary)
                    Spacer()
                    Text("防御力順")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ForEach(Array(result.sets.enumerated()), id: \.offset) { _, set in
                    resultCard(set)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func resultCard(_ set: EquipmentSet) -> some View {
        Button {
            path.append(.detail(EquipmentSetItem(set: set)))
        } label: {
            MHCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("防御力")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mhTextTertiary)
                            Text("\(set.totalDefenseMax)")
                                .font(MHFont.statNumber)
                                .foregroundStyle(Color.mhTextPrimary)
                        }
                        Spacer()
                        Text("空きスロ " + MHFormat.emptySlotSummary(
                            weapon: set.emptyWeaponSlots, armor: set.emptyArmorSlots))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mhTextSecondary)
                    }
                    Text(headline(for: set))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhTextSecondary)
                    chipRow(for: set)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func headline(for set: EquipmentSet) -> String {
        let headName = set.pieces[.head]?.name ?? set.pieces.values.first?.name ?? ""
        return "\(headName) 他\(max(0, set.pieces.count - 1))部位"
    }

    private func chipRow(for set: EquipmentSet) -> some View {
        // 条件スキル優先で最大5チップ+「…」
        let conditionSkills = set.activeSkills
            .filter { viewModel.isConditionSkill($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : viewModel.skillName($0.key) < viewModel.skillName($1.key) }
        let others = set.activeSkills
            .filter { !viewModel.isConditionSkill($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : viewModel.skillName($0.key) < viewModel.skillName($1.key) }
        let visibleOthers = others.prefix(max(0, 5 - conditionSkills.count))
        let hasMore = others.count > visibleOthers.count

        return MHFlowLayout(spacing: 6) {
            ForEach(conditionSkills, id: \.key) { entry in
                SkillChip(text: MHFormat.skillLine(viewModel.skillName(entry.key), entry.value), isCondition: true)
            }
            ForEach(Array(visibleOthers), id: \.key) { entry in
                SkillChip(text: MHFormat.skillLine(viewModel.skillName(entry.key), entry.value))
            }
            if hasMore {
                SkillChip(text: "…")
            }
        }
    }

    // MARK: - 0件・逆引き(画面設計4.4の0件時)

    private var notFoundHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.mhTextTertiary)
            Text("条件に合う装備は見つかりません")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.mhTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func reverseContent(_ outcome: CharmOracle.Outcome) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                notFoundHeader
                switch outcome {
                case .charms(let suggestions):
                    MHSectionHeader(title: "この護石があれば組めます")
                    VStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 7)
                case .relaxations(let skillIds):
                    MHSectionHeader(title: "このスキルを外せば組めます")
                    VStack(spacing: 10) {
                        ForEach(skillIds, id: \.self) { skillId in
                            relaxationRow(skillId)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 7)
                case .none:
                    Text("護石では埋まらない条件です。条件を見直してください")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func suggestionCard(_ suggestion: CharmOracle.CharmSuggestion) -> some View {
        Button {
            entryTarget = .preset(suggestion.requirement)
        } label: {
            suggestionCardBody(suggestion)
        }
    }

    private func suggestionCardBody(_ suggestion: CharmOracle.CharmSuggestion) -> some View {
        MHCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color.mhAccentWash)
                    Image(systemName: "seal")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.mhAccent)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.requirementText(suggestion.requirement))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mhTextPrimary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        RarityBadge(rarity: suggestion.minimumRarity)
                        Text("の護石で出現。入手したらタップで登録")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mhTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(13)
        }
    }

    private func relaxationRow(_ skillId: SkillId) -> some View {
        Button {
            viewModel.removeSkillAndRetry(skillId)
        } label: {
            MHCard {
                HStack {
                    Text("\(viewModel.skillName(skillId))を外すと組めます")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mhTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                .padding(13)
            }
        }
    }
}
