import SwiftUI
import MHSimulatorCore

/// 検索タブの遷移先
nonisolated enum SearchRoute: Hashable {
    case results
    case detail(EquipmentSetItem)
    case weaponSelect(String?)  // 引数: 武器種フィルタの初期値(nil=全一覧/"artian"=カスタム武器設定)
}

/// EquipmentSetをナビゲーション引数にするためのIdラッパ
nonisolated struct EquipmentSetItem: Hashable, Identifiable {
    let id = UUID()
    let set: EquipmentSet

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 検索タブのフロー(検索条件→結果→詳細)。画面設計4.1(2026-08-24改訂)
struct SearchConditionView: View {
    let dependencies: AppDependencies
    @State private var viewModel: SearchConditionViewModel
    @State private var path: [SearchRoute] = []
    @State private var showsSkillPicker = false
    @State private var showsSearchSettings = false
    @State private var showsAdFreeSheet = false
    @State private var detailSkill: Skill?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: SearchConditionViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // 入場モーション: 武器(0)→スキル条件(1)→検索ボタン(2)。DESIGN.md §7.5
                            // (VStackなのはコーチマークがセクション全体を1つの枠として指すため)
                            VStack(alignment: .leading, spacing: 0) {
                                MHSectionHeader(title: String(localized: "武器"),
                                                actionTitle: String(localized: "リセット")) {
                                    viewModel.reset()
                                }
                                    .padding(.top, 20)
                                // 武器種チップ: タップでその武器種にフィルタした武器選択へ
                                WeaponKindChips(
                                    selectedKind: selectedWeaponKind,
                                    onTap: { kind in path.append(.weaponSelect(kind)) })
                                    .padding(.top, 7)
                                weaponStatusRow
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                            }
                            .mhEntrance(0)
                            .coachMarkTarget(.weaponSection)

                            VStack(alignment: .leading, spacing: 0) {
                                MHSectionHeader(title: String(localized: "スキル条件"))
                                    .padding(.top, 20)
                                conditionList
                                    .padding(.horizontal, 16)
                                    .padding(.top, 7)
                            }
                            .mhEntrance(1)
                            .coachMarkTarget(.skillSection)
                        }
                        .padding(.bottom, 24)
                    }
                    searchButtonBar
                        .mhEntrance(2)
                }
            }
            .mhNavigationTitle(String(localized: "検索条件"))
            .safeAreaInset(edge: .top, spacing: 0) { AdBannerView(adUnitId: AdConfig.searchBannerUnitId) }
            .toolbar {
                // 広告非表示(リワード)。左上に自作アイコン(画面設計§2 2026-08-29追加)
                AdFreeToolbarButton {
                    showsAdFreeSheet = true
                }
                // 検索設定(固定・除外)。設定ありのときは赤バッジ(画面設計4.1 2026-08-24改訂)
                MHToolbarIconButton(
                    systemImage: "gearshape",
                    showsBadge: viewModel.hasEquipmentFilters,
                    coachMarkID: .searchSettingsButton
                ) {
                    showsSearchSettings = true
                }
            }
            // 初回起動コーチマーク(入場モーション完了後に開始。タブ離脱・画面遷移でtaskごとキャンセル)
            .task {
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                CoachMarkCenter.shared.startTourIfNeeded(.search)
            }
            .sheet(isPresented: $showsAdFreeSheet) {
                AdFreeSheetView()
            }
            .sheet(isPresented: $showsSkillPicker) {
                SkillPickerView(conditionViewModel: viewModel)
            }
            .sheet(isPresented: $showsSearchSettings) {
                SearchSettingsView(conditionViewModel: viewModel)
            }
            .sheet(item: $detailSkill) { skill in
                SkillDetailView(master: dependencies.master, skill: skill)
            }
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case .results:
                    SearchResultsView(
                        dependencies: dependencies,
                        conditionViewModel: viewModel,
                        path: $path)
                case .detail(let item):
                    EquipmentDetailView(
                        dependencies: dependencies,
                        item: item,
                        condition: viewModel.makeCondition())
                case .weaponSelect(let kind):
                    WeaponSelectView(conditionViewModel: viewModel, path: $path, initialKind: kind)
                }
            }
        }
    }

    /// チップのハイライト対象(カスタム武器=アーティア枠)
    private var selectedWeaponKind: String? {
        guard let kind = viewModel.selectedWeapon?.kind else { return nil }
        return kind == "custom" ? WeaponKindChips.artianKind : kind
    }

    /// 画面下部固定の検索ボタン(2026-08-24改訂)
    private var searchButtonBar: some View {
        MHPrimaryButton(title: String(localized: "検索する"), isEnabled: viewModel.canSearch) {
            // インタースティシャルの頻度カウント(表示は結果から戻るとき。画面設計§2 2026-08-29)
            InterstitialAdCoordinator.shared.recordSearch()
            path.append(.results)
        }
        .coachMarkTarget(.searchButton)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mhBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairlineFaint).frame(height: 1)
        }
    }

    /// 選択中武器の1行表示(未選択時は自動選択の案内)
    private var weaponStatusRow: some View {
        Button {
            path.append(.weaponSelect(selectedWeaponKind))
        } label: {
            MHCard {
                HStack(spacing: 8) {
                    if let weapon = viewModel.selectedWeapon {
                        Text(weapon.id == CustomWeaponConfig.weaponId
                             ? weapon.name
                             : "\(MHFormat.weaponKindLabel(weapon.kind)) \(weapon.name)")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mhTextPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(MHFormat.slotSymbols(weapon.slots))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mhTextSecondary)
                    } else {
                        Text("すべての武器から検索")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mhTextSecondary)
                        Spacer()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
        }
    }

    private var conditionList: some View {
        MHCard {
            VStack(spacing: 0) {
                ForEach(viewModel.conditions) { row in
                    conditionRow(row)
                    Rectangle()
                        .fill(Color.mhHairlineFaint)
                        .frame(height: 1)
                        .padding(.leading, 16)
                }
                addSkillRow
            }
        }
    }

    /// スキル条件リスト末尾の追加行(2026-08-24改訂: ヘッダから移動)
    private var addSkillRow: some View {
        Button {
            showsSkillPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("スキルを追加")
                    .font(.system(size: 16))
                Spacer()
            }
            .foregroundStyle(Color.mhAccent)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private func conditionRow(_ row: SearchConditionViewModel.ConditionRow) -> some View {
        HStack(spacing: 10) {
            Text(row.skill.name)
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextPrimary)
            Spacer()
            Text("Lv\(row.level)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mhAccent)
            MHStepper(
                canDecrement: row.level > 1,
                canIncrement: row.level < row.skill.maxLevel,
                onDecrement: { viewModel.setLevel(row.id, row.level - 1) },
                onIncrement: { viewModel.setLevel(row.id, row.level + 1) })
            Button {
                viewModel.removeSkill(row.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.mhDestructive)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .mhSkillDetailContextMenu { detailSkill = row.skill }
    }
}
