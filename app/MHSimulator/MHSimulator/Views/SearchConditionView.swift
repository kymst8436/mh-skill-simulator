import SwiftUI
import MHSimulatorCore

/// 検索タブの遷移先
nonisolated enum SearchRoute: Hashable {
    case results
    case detail(EquipmentSetItem)
    case weaponSelect
    case customWeapon
}

/// EquipmentSetをナビゲーション引数にするためのIdラッパ
nonisolated struct EquipmentSetItem: Hashable, Identifiable {
    let id = UUID()
    let set: EquipmentSet

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 検索タブのフロー(検索条件→結果→詳細)。画面設計4.1
struct SearchConditionView: View {
    let dependencies: AppDependencies
    @State private var viewModel: SearchConditionViewModel
    @State private var path: [SearchRoute] = []
    @State private var showsSkillPicker = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: SearchConditionViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MHSectionHeader(title: "武器")
                            .padding(.top, 20)
                        weaponRow
                            .padding(.horizontal, 16)
                            .padding(.top, 7)

                        MHSectionHeader(title: "スキル条件", actionTitle: "+ 追加") {
                            showsSkillPicker = true
                        }
                        .padding(.top, 20)
                        conditionList
                            .padding(.horizontal, 16)
                            .padding(.top, 7)

                        MHPrimaryButton(title: "検索する", isEnabled: viewModel.canSearch) {
                            path.append(.results)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                    }
                    .padding(.bottom, 24)
                }
            }
            .mhNavigationTitle("検索条件")
            .safeAreaInset(edge: .top, spacing: 0) { AdBannerView(adUnitId: AdConfig.searchBannerUnitId) }
            .toolbar {
                MHToolbarButton(title: "リセット", isEnabled: viewModel.canReset) {
                    viewModel.reset()
                }
            }
            .sheet(isPresented: $showsSkillPicker) {
                SkillPickerView(conditionViewModel: viewModel)
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
                case .weaponSelect:
                    WeaponSelectView(conditionViewModel: viewModel, path: $path)
                case .customWeapon:
                    CustomWeaponView(conditionViewModel: viewModel, path: $path)
                }
            }
        }
    }

    private var weaponRow: some View {
        Button {
            path.append(.weaponSelect)
        } label: {
            MHCard {
                HStack(spacing: 8) {
                    if let weapon = viewModel.selectedWeapon {
                        Text(weapon.id == CustomWeaponConfig.weaponId
                             ? weapon.name
                             : "\(MHFormat.weaponKindLabel(weapon.kind)) \(weapon.name)")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.mhTextPrimary)
                        Spacer()
                        Text(MHFormat.slotSymbols(weapon.slots))
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mhTextSecondary)
                    } else {
                        Text("指定なし(全武器から自動選択)")
                            .font(.system(size: 16))
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
            if viewModel.conditions.isEmpty {
                Text("スキルを追加して検索条件を作成してください")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.conditions) { row in
                        conditionRow(row)
                        if row.id != viewModel.conditions.last?.id {
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
    }
}
