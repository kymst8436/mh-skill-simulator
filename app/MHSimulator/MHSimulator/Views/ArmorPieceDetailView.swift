import SwiftUI
import MHSimulatorCore

/// 防具詳細sheet(2026-08-31追加)。スキル詳細の防具一覧・装備詳細の防具行のタップで開く。
/// 防御力・スロット・スキルに加え、同シリーズ防具の早見表(縦=スキル/横=部位、最下段に空きスロット)を表示する
struct ArmorPieceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let master: MasterDatabase
    let piece: ArmorPiece
    /// スロット表示を限界突破後にするか(検索設定トグルと連動)
    var considerLimitBreak: Bool = true
    @State private var detailSkill: Skill?

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
                        section(String(localized: "スロット")) { slotRow }
                        if !skillEntries.isEmpty {
                            section(String(localized: "スキル")) { skillRowsView }
                        }
                    }
                    .mhEntrance(2)
                    if seriesPieces.count > 1 {
                        section(String(localized: "同シリーズの防具")) { seriesMatrix }
                            .mhEntrance(3)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
        .sheet(item: $detailSkill) { skill in
            SkillDetailView(master: master, skill: skill, considerLimitBreak: considerLimitBreak)
        }
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 84, height: 1)
            Spacer()
            Text("防具詳細")
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

    // MARK: - 部品(スキル詳細4.14と同じセクション構成)

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

    /// 表示用スロット(限界突破トグルに追従。サイズ降順)
    private func displaySlots(_ piece: ArmorPiece) -> [Int] {
        (considerLimitBreak ? piece.limitBreakSlots : piece.slots).sorted(by: >)
    }

    // MARK: - 防具名+防御力・耐性

    private var summaryCard: some View {
        let resistances = zip(
            [
                String(localized: "火"), String(localized: "水"), String(localized: "雷"),
                String(localized: "氷"), String(localized: "龍"),
            ],
            piece.resistances)
        let colors: [Color] = [
            Color(mhHex: 0xC25B4A), Color(mhHex: 0x5B8FC2), Color(mhHex: 0xC9A227),
            Color(mhHex: 0x5FA8C2), Color(mhHex: 0x9678C8),
        ]
        return MHCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RarityBadge(rarity: master.armorSeries[piece.seriesId]?.rarity ?? 0)
                    GearIcon(assetName: MHFormat.pieceIconName(piece.kind), rarity: master.armorSeries[piece.seriesId]?.rarity, size: 22)
                        .accessibilityLabel(MHFormat.pieceLabel(piece.kind))
                    Text(piece.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mhTextPrimary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("防御力")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mhTextTertiary)
                    Text("\(piece.defenseMax)")
                        .font(MHFont.statNumber)
                        .foregroundStyle(Color.mhTextPrimary)
                    Spacer()
                }
                // 耐性は独立した行に置く(独語等の長いラベルが語中で折り返されるのを防ぐ)
                HStack(spacing: 9) {
                    ForEach(Array(resistances.enumerated()), id: \.offset) { index, entry in
                        Text("\(entry.0) \(entry.1)")
                            .font(.system(size: 14))
                            .foregroundStyle(colors[index])
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - スロット

    private var slotRow: some View {
        HStack {
            Text(MHFormat.slotSymbols(displaySlots(piece)))
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
    }

    // MARK: - スキル

    private var skillEntries: [(skill: Skill, level: Int)] {
        piece.skills
            .compactMap { id, level -> (Skill, Int)? in
                guard let skill = master.skills[id] else { return nil }
                return (skill, level)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.name < $1.0.name
            }
    }

    @ViewBuilder
    private var skillRowsView: some View {
        let entries = skillEntries
        ForEach(Array(entries.enumerated()), id: \.element.skill.id) { index, entry in
            HStack(spacing: 10) {
                Text(entry.skill.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
                Text("Lv\(entry.level)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mhAccent)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
            .mhSkillDetailContextMenu { detailSkill = entry.skill }
            if index < entries.count - 1 { separator }
        }
    }

    // MARK: - 同シリーズの防具(早見表)

    /// 同シリーズの全部位(頭→胴→腕→腰→脚)。自身も含めて列にする
    private var seriesPieces: [ArmorPiece] {
        let order = Dictionary(
            uniqueKeysWithValues: ArmorPieceKind.allCases.enumerated().map { ($0.element, $0.offset) })
        return master.armorPieces
            .filter { $0.seriesId == piece.seriesId }
            .sorted { (order[$0.kind] ?? 0) < (order[$1.kind] ?? 0) }
    }

    /// 行に出すスキル(シリーズ内合計レベル降順→名前順)
    private var matrixSkills: [Skill] {
        let pieces = seriesPieces
        var totals: [SkillId: Int] = [:]
        for piece in pieces {
            for (id, level) in piece.skills { totals[id, default: 0] += level }
        }
        return totals.keys
            .compactMap { master.skills[$0] }
            .sorted {
                let l = totals[$0.id] ?? 0
                let r = totals[$1.id] ?? 0
                if l != r { return l > r }
                return $0.name < $1.name
            }
    }

    private var matrixSlotRowCount: Int {
        seriesPieces.map { displaySlots($0).count }.max() ?? 0
    }

    private var seriesMatrix: some View {
        let pieces = seriesPieces
        let skills = matrixSkills
        let slotRows = matrixSlotRowCount
        return Grid(horizontalSpacing: 4, verticalSpacing: 0) {
            // ヘッダー行: 部位アイコン(自部位の列は帯で強調)
            GridRow {
                Color.clear
                    .frame(height: 1)
                ForEach(pieces, id: \.id) { entry in
                    matrixCell(isCurrent: entry.id == piece.id) {
                        Image(MHFormat.pieceIconName(entry.kind))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .accessibilityLabel(MHFormat.pieceLabel(entry.kind))
                    }
                }
            }
            matrixSeparator(columns: pieces.count + 1)
            ForEach(skills, id: \.id) { skill in
                GridRow {
                    matrixLabel(skill.name)
                    ForEach(pieces, id: \.id) { entry in
                        matrixCell(isCurrent: entry.id == piece.id) {
                            if let level = entry.skills[skill.id] {
                                Text("\(level)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.mhTextPrimary)
                            }
                        }
                    }
                }
            }
            if slotRows > 0 {
                matrixSeparator(columns: pieces.count + 1)
                // 空きスロット行: n行目に各部位のn番目のスロットサイズを表示
                ForEach(0..<slotRows, id: \.self) { index in
                    GridRow {
                        matrixLabel(index == 0 ? String(localized: "空きスロット") : "")
                        ForEach(pieces, id: \.id) { entry in
                            let slots = displaySlots(entry)
                            matrixCell(isCurrent: entry.id == piece.id) {
                                if index < slots.count {
                                    Text(MHFormat.slotSymbols([slots[index]]))
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.mhTextSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func matrixLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Color.mhTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .gridColumnAlignment(.leading)
    }

    /// 早見表のセル(固定幅32。自部位の列は縦に連続した帯になるようセル背景で塗る)。
    /// 値なしでもセルを潰さない(潰れると後続セルが左に詰まり列がずれる)ようZStackで常に描画する
    private func matrixCell(isCurrent: Bool, @ViewBuilder content: () -> some View) -> some View {
        ZStack {
            Color.clear
            content()
        }
        .frame(width: 32)
        .frame(minHeight: 34, maxHeight: .infinity)
        .background(isCurrent ? Color.mhAccentWash : .clear)
    }

    private func matrixSeparator(columns: Int) -> some View {
        GridRow {
            Rectangle()
                .fill(Color.mhHairlineFaint)
                .frame(height: 1)
                .gridCellColumns(columns)
        }
    }
}
