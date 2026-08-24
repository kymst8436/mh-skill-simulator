import SwiftUI
import MHSimulatorCore

/// 武器選択(画面設計4.3。2026-08-24改訂)。
/// 上部の武器種チップで武器種を切り替える。「アーティア」選択時は
/// 武器一覧の代わりにカスタム武器設定フォームを表示する
struct WeaponSelectView: View {
    @Environment(\.dismiss) private var dismiss
    let conditionViewModel: SearchConditionViewModel
    @Binding var path: [SearchRoute]
    @State private var searchText = ""
    @State private var kindFilter: String?

    private var master: MasterDatabase { conditionViewModel.dependencies.master }

    init(conditionViewModel: SearchConditionViewModel, path: Binding<[SearchRoute]>, initialKind: String? = nil) {
        self.conditionViewModel = conditionViewModel
        _path = path
        _kindFilter = State(initialValue: initialKind)
    }

    private var isArtianMode: Bool { kindFilter == WeaponKindChips.artianKind }

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // 武器種チップ(この画面内でも切替可能。アーティア=カスタム武器設定)
                WeaponKindChips(selectedKind: kindFilter) { kind in
                    kindFilter = (kindFilter == kind) ? nil : kind
                }
                .padding(.vertical, 12)
                .mhEntrance(0)

                if isArtianMode {
                    CustomWeaponForm(conditionViewModel: conditionViewModel) {
                        dismiss()
                    }
                } else {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .mhEntrance(1)
                    weaponList
                        .mhEntrance(2)
                }
            }
        }
        .mhNavigationTitle("武器を選択")
        .navigationBarBackButtonHidden(true)
        .toolbar { MHBackButton { dismiss() } }
    }

    private var visibleWeapons: [Weapon] {
        master.weapons
            .filter { weapon in
                (kindFilter == nil || weapon.kind == kindFilter)
                    && weapon.name.mhContains(searchText)
            }
            .sorted {
                if $0.rarity != $1.rarity { return $0.rarity > $1.rarity }
                return $0.name.compare($1.name, locale: Locale(identifier: "ja_JP")) == .orderedAscending
            }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextTertiary)
            TextField("", text: $searchText,
                      prompt: Text("武器名で検索").foregroundStyle(Color.mhTextTertiary))
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextPrimary)
            Text("\(visibleWeapons.count)本")
                .font(.system(size: 13))
                .foregroundStyle(Color.mhTextTertiary)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
    }

    @ViewBuilder
    private var weaponList: some View {
        if visibleWeapons.isEmpty {
            MHEmptyState(
                systemImage: "magnifyingglass",
                title: "「\(searchText)」に一致する武器はありません")
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    clearRow
                    separator
                    ForEach(visibleWeapons, id: \.id) { weapon in
                        weaponRow(weapon)
                        separator
                    }
                }
            }
        }
    }

    private var clearRow: some View {
        Button {
            conditionViewModel.selectWeapon(nil)
            dismiss()
        } label: {
            HStack {
                Text("指定なし(全武器から自動選択)")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextSecondary)
                Spacer()
                if conditionViewModel.selectedWeapon == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.mhAccent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private func weaponRow(_ weapon: Weapon) -> some View {
        let isSelected = conditionViewModel.selectedWeapon?.id == weapon.id
        let skillSummary = weapon.skills
            .compactMap { id, level in master.skills[id].map { MHFormat.skillLine($0.name, level) } }
            .sorted()
            .joined(separator: "・")
        return Button {
            conditionViewModel.selectWeapon(weapon)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weapon.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mhTextPrimary)
                    if !skillSummary.isEmpty {
                        Text(skillSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mhTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                RarityBadge(rarity: weapon.rarity)
                Text(MHFormat.slotSymbols(weapon.slots))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mhTextSecondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.mhAccent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(isSelected ? Color.mhAccentWash : .clear)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }
}
