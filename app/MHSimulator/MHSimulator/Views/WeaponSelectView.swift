import SwiftUI
import MHSimulatorCore

/// 武器選択(画面設計4.3)。検索に反映する武器を1つ選ぶ、または解除する
struct WeaponSelectView: View {
    @Environment(\.dismiss) private var dismiss
    let conditionViewModel: SearchConditionViewModel
    @State private var searchText = ""
    @State private var kindFilter: String?

    private var master: MasterDatabase { conditionViewModel.dependencies.master }

    init(conditionViewModel: SearchConditionViewModel) {
        self.conditionViewModel = conditionViewModel
        _kindFilter = State(initialValue: conditionViewModel.selectedWeapon?.kind)
    }

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                controls
                    .padding(16)
                weaponList
            }
        }
        .mhNavigationTitle("武器を選択")
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

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextTertiary)
                TextField("", text: $searchText,
                          prompt: Text("武器名で検索").foregroundStyle(Color.mhTextTertiary))
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextPrimary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.mhSurfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))

            HStack {
                Menu {
                    Button("すべて") { kindFilter = nil }
                    ForEach(MHFormat.weaponKinds, id: \.self) { kind in
                        Button(MHFormat.weaponKindLabel(kind)) { kindFilter = kind }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(kindFilter.map(MHFormat.weaponKindLabel) ?? "すべての武器種")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mhAccent)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.mhAccent)
                    }
                }
                Spacer()
                Text("\(visibleWeapons.count)本")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
            }
        }
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
                Text("武器を使わない")
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
