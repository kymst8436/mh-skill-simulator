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
        .task {
            viewModel.start()
            viewModel.loadWishlistRequirements()
        }
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
        // 一覧はコンテナごと1単位で入場(DESIGN.md §7.5)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    // truncatedは件数上限・時間予算どちらの打ち切りでもtrue(2026-08-26)
                    Text(result.truncated
                         ? "\(result.sets.count)件(打ち切りあり。条件を絞ると精度が上がります)"
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

                // 一覧先頭+5件ごとにネイティブ広告(画面設計§2。2026-08-24)
                NativeAdSlot()
                ForEach(Array(result.sets.enumerated()), id: \.offset) { index, set in
                    resultCard(set)
                        .padding(.horizontal, 16)
                    if (index + 1) % 10 == 0 {
                        NativeAdSlot()
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .mhEntrance(0)
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
                        Text("空きスロ " + MHFormat.slotCountSummary(
                            weapon: set.emptyWeaponSlots, armor: set.emptyArmorSlots))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mhTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    pieceRow(for: set)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 部位名を頭・胴・腕・腰・脚の順で1行横スクロール表示(2026-08-24改訂)
    private func pieceRow(for set: EquipmentSet) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                let names = ArmorPieceKind.allCases.compactMap { set.pieces[$0]?.name }
                Text(names.joined(separator: "・"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mhTextSecondary)
                    .lineLimit(1)
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
                NativeAdSlot()  // 広告は入場モーション対象外(DESIGN.md §7.5)
                    .padding(.top, 12)
                notFoundHeader
                    .mhEntrance(0)
                Group {
                    switch outcome.kind {
                    case .charms(let suggestions):
                        MHSectionHeader(title: "この護石があれば組めます")
                        VStack(spacing: 10) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                suggestionCard(suggestion)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        if !outcome.isExhaustive { truncationNote }
                    case .relaxations(let skillIds):
                        MHSectionHeader(title: "このスキルを外せば組めます")
                        VStack(spacing: 10) {
                            ForEach(skillIds, id: \.self) { skillId in
                                relaxationRow(skillId)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        if !outcome.isExhaustive { truncationNote }
                    case .none:
                        if outcome.isExhaustive {
                            Text("護石では埋まらない条件です。条件を見直してください")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.mhTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 32)
                        } else {
                            // 時間予算内に探索しきれなかった(真のゼロ件とは区別する。2026-08-26)
                            VStack(spacing: 10) {
                                Text("時間内に狙える護石を見つけられませんでした")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.mhTextSecondary)
                                    .multilineTextAlignment(.center)
                                Button("再試行") { viewModel.retry() }
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.mhAccent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 32)
                        }
                    }
                }
                .mhEntrance(1)
            }
            .padding(.bottom, 24)
        }
    }

    /// 打ち切り注記(逆引きが時間予算・葉予算で途中終了した場合)
    private var truncationNote: some View {
        Text("時間の都合で探索を打ち切ったため、他にも候補がある可能性があります")
            .font(.system(size: 12))
            .foregroundStyle(Color.mhTextTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func suggestionCard(_ suggestion: CharmOracle.CharmSuggestion) -> some View {
        Button {
            entryTarget = .preset(suggestion.requirement)
        } label: {
            suggestionCardBody(suggestion)
        }
        // ウィッシュリストへワンタップ登録(画面設計4.4 2026-08-25追加)
        .overlay(alignment: .topTrailing) {
            wishlistButton(suggestion.requirement)
        }
    }

    /// 逆引き候補カード右上のウィッシュリスト登録ボタン。登録済みは塗りつぶし表示
    private func wishlistButton(_ requirement: CharmRules.Requirement) -> some View {
        let isAdded = viewModel.isInWishlist(requirement)
        return Button {
            viewModel.addToWishlist(requirement)
        } label: {
            Image(systemName: isAdded ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15))
                .foregroundStyle(isAdded ? Color.mhAccent : Color.mhTextSecondary)
                .frame(width: 40, height: 40)
        }
        .disabled(isAdded)
        .accessibilityLabel(isAdded ? "ウィッシュリスト登録済み" : "ウィッシュリストに追加")
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
