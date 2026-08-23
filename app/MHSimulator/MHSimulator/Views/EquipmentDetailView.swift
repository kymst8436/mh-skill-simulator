import SwiftUI
import MHSimulatorCore

/// 装備詳細(画面設計4.5)。検索結果1件の内訳を表示専用で確認する
struct EquipmentDetailView: View {
    let dependencies: AppDependencies
    let item: EquipmentSetItem
    let condition: SearchCondition
    let weapon: Weapon?
    @Environment(\.dismiss) private var dismiss

    private var equipment: EquipmentSet { item.set }
    private var master: MasterDatabase { dependencies.master }

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    section("装備") { equipmentRows }
                    section("装飾品") { decorationRows }
                    section("発動スキル") { skillRows }
                    section("空きスロット") {
                        row {
                            Text("武器 \(MHFormat.slotSymbols(equipment.emptyWeaponSlots)) / 防具 \(MHFormat.slotSymbols(equipment.emptyArmorSlots))")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.mhTextPrimary)
                            Spacer()
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .mhNavigationTitle("装備詳細")
        .navigationBarBackButtonHidden(true)
        .toolbar { MHBackButton { dismiss() } }
    }

    // MARK: - 部品

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MHSectionHeader(title: title)
                .padding(.top, 16)
            MHCard {
                VStack(spacing: 0) { content() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    // MARK: - サマリ

    private var summaryCard: some View {
        let resistances = zip(
            ["火", "水", "雷", "氷", "龍"],
            equipment.totalResistances)
        let colors: [Color] = [
            Color(mhHex: 0xC25B4A), Color(mhHex: 0x5B8FC2), Color(mhHex: 0xC9A227),
            Color(mhHex: 0x5FA8C2), Color(mhHex: 0x9678C8),
        ]
        return MHCard {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("防御力")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mhTextTertiary)
                    Text("\(equipment.totalDefenseMax)")
                        .font(MHFont.statNumber)
                        .foregroundStyle(Color.mhTextPrimary)
                }
                Spacer()
                HStack(spacing: 9) {
                    ForEach(Array(resistances.enumerated()), id: \.offset) { index, entry in
                        Text("\(entry.0) \(entry.1)")
                            .font(.system(size: 14))
                            .foregroundStyle(colors[index])
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - 装備

    @ViewBuilder
    private var equipmentRows: some View {
        if let weapon {
            row {
                label("武器")
                name(weapon.name)
                Spacer()
                slot(MHFormat.slotSymbols(weapon.slots))
            }
            separator
        }
        ForEach(ArmorPieceKind.allCases, id: \.self) { kind in
            if let piece = equipment.pieces[kind] {
                row {
                    label(MHFormat.pieceLabel(kind))
                    name(piece.name)
                    Spacer()
                    slot(MHFormat.slotSymbols(piece.slots))
                }
                separator
            }
        }
        row {
            label("護石")
            name(charmText)
            Spacer()
            if equipment.charm.source != .none {
                slot(MHFormat.emptySlotSummary(
                    weapon: equipment.charm.weaponSlots, armor: equipment.charm.armorSlots))
            }
        }
    }

    private var charmText: String {
        switch equipment.charm.source {
        case .none:
            return "なし"
        case .fixed, .owned:
            if equipment.charm.skills.isEmpty { return equipment.charm.name }
            return equipment.charm.name
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.mhTextTertiary)
            .frame(width: 44, alignment: .leading)
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color.mhTextPrimary)
    }

    private func slot(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Color.mhTextSecondary)
    }

    // MARK: - 装飾品

    @ViewBuilder
    private var decorationRows: some View {
        if equipment.decorations.isEmpty {
            row {
                Text("装飾品: なし")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextTertiary)
                Spacer()
            }
        } else {
            ForEach(Array(equipment.decorations.enumerated()), id: \.offset) { index, assignment in
                row {
                    name(assignment.decoration.name)
                    Spacer()
                    slot("→ \(ownerLabel(assignment.owner)) スロ\(MHFormat.slotSymbols([assignment.slotSize]))")
                }
                if index < equipment.decorations.count - 1 { separator }
            }
        }
    }

    private func ownerLabel(_ owner: DecorationAssignment.SlotOwner) -> String {
        switch owner {
        case .weapon: "武器"
        case .armor(let kind): MHFormat.pieceLabel(kind)
        case .charmWeapon: "護石(武)"
        case .charmArmor: "護石"
        }
    }

    // MARK: - 発動スキル

    @ViewBuilder
    private var skillRows: some View {
        let sorted = sortedSkills
        ForEach(Array(sorted.enumerated()), id: \.offset) { index, entry in
            row {
                name(MHFormat.skillLine(entry.name, entry.level))
                if entry.isCondition {
                    Text("★条件")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mhAccentSoft)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.mhAccentWash)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                Spacer()
                if let kindNote = entry.kindNote {
                    slot(kindNote)
                }
            }
            if index < sorted.count - 1 { separator }
        }
    }

    private struct SkillRow {
        let name: String
        let level: Int
        let isCondition: Bool
        let kindNote: String?
    }

    private var sortedSkills: [SkillRow] {
        equipment.activeSkills
            .compactMap { id, level -> SkillRow? in
                guard let skill = master.skills[id] else { return nil }
                let kindNote: String?
                switch skill.kind {
                case .set: kindNote = "シリーズ"
                case .group: kindNote = "グループ"
                default: kindNote = nil
                }
                return SkillRow(
                    name: skill.name, level: level,
                    isCondition: condition.requiredSkills[id] != nil,
                    kindNote: kindNote)
            }
            .sorted {
                if $0.isCondition != $1.isCondition { return $0.isCondition }
                if $0.level != $1.level { return $0.level > $1.level }
                return $0.name < $1.name
            }
    }
}
