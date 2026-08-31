import SwiftUI
import MHSimulatorCore

/// スキル詳細sheet(画面設計4.14)。スキル一覧行の長押しメニュー「スキル詳細」から開く。
/// スキル名・説明・発動条件(シリーズ/グループ)・レベルごとの効果・そのスキルを持つ防具を表示する
struct SkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let master: MasterDatabase
    let skill: Skill
    /// 防具一覧のスロット表示を限界突破後にするか(検索設定トグルと連動。2026-08-31追加)
    var considerLimitBreak: Bool = true
    /// 防具一覧のレア度フィルター(nil=すべて。2026-08-31追加)
    @State private var rarityFilter: Int?
    /// 防具一覧のスキルレベルフィルター(nil=すべて。装備/武器スキルのみ)
    @State private var levelFilter: Int?
    /// タップで開く防具詳細(2026-08-31追加)
    @State private var detailPiece: ArmorPiece?

    var body: some View {
        VStack(spacing: 0) {
            header
                .mhEntrance(0)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summaryCard
                        .padding(.horizontal, 16)
                        .mhEntrance(1)
                    Group {
                        if !bonusRanks.isEmpty {
                            section(String(localized: "発動条件")) { bonusRankRows }
                        }
                        if !levelEffects.isEmpty {
                            section(String(localized: "レベルごとの効果")) { levelEffectRows }
                        }
                    }
                    .mhEntrance(2)
                    if !allArmorRows.isEmpty {
                        armorSection
                            .mhEntrance(3)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
        .sheet(item: $detailPiece) { piece in
            ArmorPieceDetailView(master: master, piece: piece, considerLimitBreak: considerLimitBreak)
        }
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 84, height: 1)
            Spacer()
            Text("スキル詳細")
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

    // MARK: - 部品(装備詳細4.5と同じセクション構成)

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

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    /// ゲーム内文言の固定改行を除去する(可変幅のUIでは折り返しに任せる)
    private func inlineText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "")
    }

    // MARK: - スキル名+説明

    private var summaryCard: some View {
        MHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(MHFormat.kindLabel(skill.kind))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mhTextSecondary)
                        .padding(.vertical, 2)
                        .frame(width: 52)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
                    Text(skill.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mhTextPrimary)
                    Spacer()
                    Text("最大Lv\(skill.maxLevel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                if let summary = skill.summary {
                    Text(inlineText(summary))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 発動条件(シリーズ/グループスキル)

    /// 部位数→発動レベル(昇順)
    private var bonusRanks: [(pieces: Int, level: Int)] {
        guard skill.kind == .set || skill.kind == .group else { return [] }
        return master.bonusRanks(forSkill: skill.id)
            .sorted { $0.key < $1.key }
            .map { (pieces: $0.key, level: $0.value) }
    }

    @ViewBuilder
    private var bonusRankRows: some View {
        let ranks = bonusRanks
        ForEach(Array(ranks.enumerated()), id: \.offset) { index, rank in
            HStack(spacing: 10) {
                Text("\(rank.pieces)部位")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mhAccent)
                    .fixedSize()
                    .frame(minWidth: 52, alignment: .leading)
                Text("Lv\(rank.level)発動")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            if index < ranks.count - 1 { separator }
        }
    }

    // MARK: - レベルごとの効果

    private var levelEffects: [(level: Int, effect: String)] {
        skill.levelEffects
            .sorted { $0.key < $1.key }
            .map { (level: $0.key, effect: $0.value) }
    }

    @ViewBuilder
    private var levelEffectRows: some View {
        let effects = levelEffects
        ForEach(Array(effects.enumerated()), id: \.offset) { index, entry in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Lv\(entry.level)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mhAccent)
                    .frame(width: 42, alignment: .leading)
                Text(inlineText(entry.effect))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mhTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if index < effects.count - 1 { separator }
        }
    }

    // MARK: - このスキルを持つ防具

    private struct ArmorRow: Identifiable {
        let id: Int64
        let seriesId: Int32
        let rarity: Int
        let pieceOrder: Int
        let pieceKind: ArmorPieceKind
        let name: String
        let slots: [Int]
        /// スキルレベル(シリーズ/グループスキルは部位数で発動するため出さない)
        let level: Int?
        /// タップで防具詳細を開くための元データ(2026-08-31追加)
        let piece: ArmorPiece
    }

    /// レア度降順→シリーズ→部位順(頭→胴→腕→腰→脚)。フィルター適用前の全件
    private var allArmorRows: [ArmorRow] {
        let pieceOrder = Dictionary(
            uniqueKeysWithValues: ArmorPieceKind.allCases.enumerated().map { ($0.element, $0.offset) })
        return master.armorPieces(withSkill: skill.id)
            .map { piece in
                ArmorRow(
                    id: piece.id,
                    seriesId: piece.seriesId,
                    rarity: master.armorSeries[piece.seriesId]?.rarity ?? 0,
                    pieceOrder: pieceOrder[piece.kind] ?? 0,
                    pieceKind: piece.kind,
                    name: piece.name,
                    slots: considerLimitBreak ? piece.limitBreakSlots : piece.slots,
                    level: skill.kind == .armor || skill.kind == .weapon
                        ? piece.skills[skill.id] : nil,
                    piece: piece)
            }
            .sorted {
                if $0.rarity != $1.rarity { return $0.rarity > $1.rarity }
                if $0.seriesId != $1.seriesId { return $0.seriesId < $1.seriesId }
                return $0.pieceOrder < $1.pieceOrder
            }
    }

    private var armorRows: [ArmorRow] {
        allArmorRows.filter {
            (rarityFilter == nil || $0.rarity == rarityFilter)
                && (levelFilter == nil || $0.level == levelFilter)
        }
    }

    /// フィルター候補(全件から算出。選択肢が1つしかないメニューは出さない)
    private var availableRarities: [Int] {
        Set(allArmorRows.map(\.rarity)).sorted(by: >)
    }

    private var availableLevels: [Int] {
        Set(allArmorRows.compactMap(\.level)).sorted()
    }

    /// レア度・スキルレベルのフィルター付きセクション(2026-08-31追加)
    private var armorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("このスキルを持つ防具")
                    .font(.system(size: 12))
                    .tracking(1)
                    .foregroundStyle(Color.mhTextTertiary)
                Spacer()
                if availableRarities.count > 1 {
                    filterMenu(
                        selection: $rarityFilter,
                        options: availableRarities,
                        unsetLabel: String(localized: "レア度"),
                        optionLabel: { String(localized: "レア\($0)") },
                        selectedLabel: { "R\($0)" })
                }
                if availableLevels.count > 1 {
                    filterMenu(
                        selection: $levelFilter,
                        options: availableLevels,
                        unsetLabel: String(localized: "スキルLv"),
                        optionLabel: { String(localized: "Lv\($0)") },
                        selectedLabel: { String(localized: "Lv\($0)") })
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            MHCard {
                VStack(spacing: 0) {
                    if armorRows.isEmpty {
                        Text("条件に一致する防具はありません")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mhTextTertiary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    } else {
                        armorPieceRows
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    /// 単一選択フィルターメニュー(nil=すべて。選択中はチェックマーク+アクセント色)
    private func filterMenu(
        selection: Binding<Int?>,
        options: [Int],
        unsetLabel: String,
        optionLabel: @escaping (Int) -> String,
        selectedLabel: (Int) -> String
    ) -> some View {
        let isActive = selection.wrappedValue != nil
        return Menu {
            Button {
                selection.wrappedValue = nil
            } label: {
                if isActive {
                    Text("すべて")
                } else {
                    Label("すべて", systemImage: "checkmark")
                }
            }
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = (selection.wrappedValue == option) ? nil : option
                } label: {
                    if selection.wrappedValue == option {
                        Label(optionLabel(option), systemImage: "checkmark")
                    } else {
                        Text(optionLabel(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selection.wrappedValue.map(selectedLabel) ?? unsetLabel)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.mhAccent : Color.mhTextSecondary)
        }
    }

    @ViewBuilder
    private var armorPieceRows: some View {
        let rows = armorRows
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            Button {
                detailPiece = row.piece
            } label: {
                HStack(spacing: 10) {
                    RarityBadge(rarity: row.rarity)
                    Image(MHFormat.pieceIconName(row.pieceKind))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .accessibilityLabel(MHFormat.pieceLabel(row.pieceKind))
                    Text(row.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                    Spacer()
                    Text(MHFormat.slotSymbols(row.slots))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhTextSecondary)
                    if let level = row.level {
                        Text("Lv\(level)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mhAccent)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if index < rows.count - 1 { separator }
        }
    }
}

/// スキル一覧の行に長押しメニュー「スキル詳細」を付ける共通modifier
extension View {
    func mhSkillDetailContextMenu(onSelect: @escaping () -> Void) -> some View {
        contextMenu {
            Button {
                onSelect()
            } label: {
                Label("スキル詳細", systemImage: "info.circle")
            }
        }
    }
}
