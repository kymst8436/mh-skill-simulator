import SwiftUI
import MHSimulatorCore

/// 装備詳細(画面設計4.5)。検索結果1件の内訳を確認し、マイセットへ保存できる(画面設計4.15 2026-08-29追加)
struct EquipmentDetailView: View {
    let dependencies: AppDependencies
    let item: EquipmentSetItem
    let condition: SearchCondition
    /// マイセット保存ボタンを出すか(マイセットタブから開いた詳細ではfalse。画面設計4.15)
    var allowsSave = true
    @Environment(\.dismiss) private var dismiss
    @State private var detailSkill: Skill?
    /// タップで開く防具詳細(2026-08-31追加)
    @State private var detailPiece: ArmorPiece?
    @State private var showsSaveAlert = false
    @State private var saveName = ""
    @State private var didSaveToMySets = false
    @State private var saveErrorMessage: String?
    @State private var showsSetLimitAlert = false
    @State private var showsProSheet = false

    private var weapon: Weapon? { item.set.weapon }

    private var equipment: EquipmentSet { item.set }
    private var master: MasterDatabase { dependencies.master }

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // 上部固定(スクロールしない)。広告は入場モーション対象外
                NativeAdSlot(adUnitId: AdConfig.detailNativeAdUnitId)
                    .padding(.top, 12)
                scrollContent
            }
        }
        .mhNavigationTitle(String(localized: "装備詳細"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            MHBackButton { dismiss() }
            if allowsSave {
                // 二重保存防止のため保存後は無効化(同じセットを複数回保存する用途は想定しない)
                MHToolbarButton(
                    title: didSaveToMySets ? String(localized: "保存済み") : String(localized: "保存"),
                    isEnabled: !didSaveToMySets) {
                    // 無料版はマイセット5個まで(2026-08-29追加)。上限到達時はPro版への導線を出す
                    guard canSaveMoreSets else {
                        showsSetLimitAlert = true
                        return
                    }
                    saveName = defaultSaveName
                    showsSaveAlert = true
                }
            }
        }
        .sheet(item: $detailSkill) { skill in
            SkillDetailView(
                master: master, skill: skill,
                considerLimitBreak: dependencies.searchFilters.considerLimitBreak)
        }
        .sheet(item: $detailPiece) { piece in
            ArmorPieceDetailView(
                master: master, piece: piece,
                considerLimitBreak: dependencies.searchFilters.considerLimitBreak)
        }
        .alert("マイセットに保存", isPresented: $showsSaveAlert) {
            TextField("セット名", text: $saveName)
            Button("保存") { saveToMySets() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この装備セットをマイセットタブに保存します")
        }
        .alert(
            saveErrorMessage ?? "",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } })
        ) {
            Button("OK") {}
        }
        .alert("マイセットの上限", isPresented: $showsSetLimitAlert) {
            Button("Pro版について") { showsProSheet = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("無料版で保存できるマイセットは\(ProStore.freeMySetLimit)個までです。Pro版にアップグレードすると上限なく保存できます")
        }
        .sheet(isPresented: $showsProSheet) {
            NavigationStack { ProPurchaseView() }
        }
    }

    // MARK: - マイセット保存(画面設計4.15 2026-08-29追加)

    /// 既定のセット名(条件スキル最大2件。条件がなければ「装備セット」)
    private var defaultSaveName: String {
        let names = sortedSkills.filter(\.isCondition).map(\.name)
        guard !names.isEmpty else { return String(localized: "装備セット") }
        return names.prefix(2).joined(separator: String(localized: "・"))
            + (names.count > 2 ? String(localized: " ほか") : "")
    }

    /// 無料版の上限判定(Pro版は無制限)。件数取得に失敗した場合は保存を妨げない
    private var canSaveMoreSets: Bool {
        if ProStore.shared.isPro { return true }
        guard let count = try? dependencies.userStore.countSavedSets() else { return true }
        return count < ProStore.freeMySetLimit
    }

    private func saveToMySets() {
        guard canSaveMoreSets else {
            showsSetLimitAlert = true
            return
        }
        let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = SavedEquipmentSet(
            name: trimmed.isEmpty ? defaultSaveName : trimmed,
            set: equipment,
            conditionSkills: condition.requiredSkills)
        do {
            try dependencies.userStore.insertSavedSet(saved)
            didSaveToMySets = true
        } catch {
            saveErrorMessage = String(localized: "保存できませんでした。端末の空き容量をご確認ください")
        }
    }

    private var scrollContent: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 入場モーション: 上から順にセクション単位(DESIGN.md §7.5)
                    summaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .mhEntrance(0)
                    section(String(localized: "装備")) { equipmentRows }
                        .mhEntrance(1)
                    section(String(localized: "装飾品")) { decorationRows }
                        .mhEntrance(2)
                    section(String(localized: "発動スキル")) { skillRows }
                        .mhEntrance(3)
                    if !inactiveBonusRows.isEmpty {
                        section(String(localized: "未発動のシリーズ・グループスキル")) { inactiveRows }
                            .mhEntrance(4)
                    }
                    section(String(localized: "空きスロット")) {
                        row {
                            Text("武器 \(MHFormat.slotSymbols(equipment.emptyWeaponSlots)) / 防具 \(MHFormat.slotSymbols(equipment.emptyArmorSlots))")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.mhTextPrimary)
                            Spacer()
                        }
                    }
                    .mhEntrance(5)
                }
                .padding(.bottom, 24)
        }
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
            [
                String(localized: "火"), String(localized: "水"), String(localized: "雷"),
                String(localized: "氷"), String(localized: "龍"),
            ],
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
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(resistances.enumerated()), id: \.offset) { index, entry in
                        VStack(spacing: 2) {
                            Text(entry.0)
                                .font(.system(size: 11))
                                .foregroundStyle(colors[index])
                            Text("\(entry.1)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.mhTextPrimary)
                        }
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
                if let iconName = MHFormat.weaponIconName(weapon.kind) {
                    icon(iconName, accessibility: String(localized: "武器"))
                } else {
                    label(String(localized: "武器"))
                }
                name(weapon.name)
                Spacer()
                slot(MHFormat.slotSymbols(weapon.slots))
            }
            separator
        }
        ForEach(ArmorPieceKind.allCases, id: \.self) { kind in
            if let piece = equipment.pieces[kind] {
                // タップで防具詳細を開く(2026-08-31追加)。スナップショットはスロットが検索時設定で
                // 差し替え済みのため、マスタの同一防具を引き直して基準値から表示する
                Button {
                    detailPiece = master.armorPieces.first { $0.id == piece.id } ?? piece
                } label: {
                    row {
                        icon(MHFormat.pieceIconName(kind), accessibility: MHFormat.pieceLabel(kind))
                        name(piece.name)
                        Spacer()
                        slot(MHFormat.slotSymbols(piece.slots))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                separator
            }
        }
        row {
            icon(MHFormat.charmIconName, accessibility: String(localized: "護石"))
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
            return String(localized: "なし")
        case .fixed, .owned:
            if equipment.charm.skills.isEmpty { return equipment.charm.name }
            return equipment.charm.name
        }
    }

    /// 装備行の先頭アイコン(ラベル列と同じ幅44で名前の縦位置を揃える)
    private func icon(_ assetName: String, accessibility: String) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 26, height: 26)
            .frame(width: 44, alignment: .leading)
            .accessibilityLabel(accessibility)
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
                    name(decorationLabel(assignment))
                    Spacer()
                    slot(String(
                        localized: "→ \(ownerLabel(assignment.owner)) スロ\(MHFormat.slotSymbols([assignment.slotSize]))"))
                }
                if index < equipment.decorations.count - 1 { separator }
            }
        }
    }

    /// 代替可能な枠は具体名の代わりに「<スキル名>の珠【サイズ】いずれか」(画面設計4.5。2026-08-29)。
    /// 条件: 必要分が単一スキル かつ 枠サイズ以下で必要分を満たせる装飾品(除外適用後)が2種類以上
    private func decorationLabel(_ assignment: DecorationAssignment) -> String {
        guard assignment.required.count == 1,
              let (skillId, level) = assignment.required.first,
              let skillName = master.skills[skillId]?.name else {
            return assignment.decoration.name
        }
        let target: DecorationTarget = switch assignment.owner {
        case .weapon, .charmWeapon: .weapon
        case .armor, .charmArmor: .armor
        }
        let alternatives = master.decorations(
            satisfying: assignment.required, target: target, maxSize: assignment.slotSize,
            excluding: condition.excludedDecorationIds)
        guard alternatives.count >= 2 else { return assignment.decoration.name }
        // Lv表記も表示言語に合わせる(スキル名+レベルの共通書式を再利用)
        let skillText = level >= 2 ? MHFormat.skillLine(skillName, level) : skillName
        return String(localized: "\(skillText)の珠【\(assignment.slotSize)】いずれか")
    }

    private func ownerLabel(_ owner: DecorationAssignment.SlotOwner) -> String {
        switch owner {
        case .weapon: String(localized: "武器")
        case .armor(let kind): MHFormat.pieceLabel(kind)
        case .charmWeapon: String(localized: "護石(武)")
        case .charmArmor: String(localized: "護石")
        }
    }

    // MARK: - 発動スキル(2026-08-24改訂: バッジ先頭+寄与装備アイコン)

    @ViewBuilder
    private var skillRows: some View {
        let sorted = sortedSkills
        ForEach(Array(sorted.enumerated()), id: \.offset) { index, entry in
            row {
                kindBadge(entry.kind)
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
                contributorIcons(entry.contributors)
            }
            .contentShape(Rectangle())
            .mhSkillDetailContextMenu { detailSkill = master.skills[entry.id] }
            if index < sorted.count - 1 { separator }
        }
    }

    /// 未発動のシリーズ/グループスキル(部位数不足。2026-08-24追加)
    @ViewBuilder
    private var inactiveRows: some View {
        let rows = inactiveBonusRows
        ForEach(Array(rows.enumerated()), id: \.offset) { index, entry in
            row {
                kindBadge(entry.kind)
                Text(entry.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextSecondary)
                Text("\(entry.currentPieces)/\(entry.requiredPieces)部位")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                Spacer()
                contributorIcons(entry.contributors)
            }
            .contentShape(Rectangle())
            .mhSkillDetailContextMenu { detailSkill = master.skills[entry.id] }
            if index < rows.count - 1 { separator }
        }
    }

    /// 行先頭の分類バッジ(スキル選択画面と同一の見た目)
    private func kindBadge(_ kind: SkillKind) -> some View {
        Text(MHFormat.kindLabel(kind))
            .font(.system(size: 11))
            .foregroundStyle(Color.mhTextSecondary)
            .padding(.vertical, 2)
            .frame(width: 52)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
    }

    /// 寄与装備のアイコン列(武器→頭→胴→腕→腰→脚→護石の順)
    @ViewBuilder
    private func contributorIcons(_ contributors: [Contributor]) -> some View {
        HStack(spacing: 5) {
            ForEach(contributors, id: \.self) { contributor in
                switch contributor {
                case .weapon:
                    if let weapon, let iconName = MHFormat.weaponIconName(weapon.kind) {
                        contributorIcon(iconName, accessibility: String(localized: "武器"))
                    } else {
                        Text("武")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mhTextTertiary)
                    }
                case .piece(let kind):
                    contributorIcon(MHFormat.pieceIconName(kind), accessibility: MHFormat.pieceLabel(kind))
                case .charm:
                    contributorIcon(MHFormat.charmIconName, accessibility: String(localized: "護石"))
                }
            }
        }
    }

    private func contributorIcon(_ assetName: String, accessibility: String) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibility)
    }

    // MARK: - スキル行の組み立て

    private enum Contributor: Hashable {
        case weapon
        case piece(ArmorPieceKind)
        case charm
    }

    private struct SkillRow {
        let id: SkillId
        let name: String
        let level: Int
        let kind: SkillKind
        let isCondition: Bool
        let contributors: [Contributor]
    }

    private struct InactiveBonusRow {
        let id: SkillId
        let name: String
        let kind: SkillKind
        let currentPieces: Int
        let requiredPieces: Int
        let contributors: [Contributor]
    }

    private var sortedSkills: [SkillRow] {
        equipment.activeSkills
            .compactMap { id, level -> SkillRow? in
                guard let skill = master.skills[id] else { return nil }
                return SkillRow(
                    id: id, name: skill.name, level: level, kind: skill.kind,
                    isCondition: condition.requiredSkills[id] != nil,
                    contributors: contributors(of: id, kind: skill.kind))
            }
            .sorted {
                if $0.isCondition != $1.isCondition { return $0.isCondition }
                if $0.level != $1.level { return $0.level > $1.level }
                return $0.name < $1.name
            }
    }

    /// 部位数不足で発動していないシリーズ/グループスキル
    private var inactiveBonusRows: [InactiveBonusRow] {
        var pieceCount: [SkillId: Int] = [:]
        var minPieces: [SkillId: Int] = [:]
        for piece in equipment.pieces.values {
            guard let series = master.armorSeries[piece.seriesId] else { continue }
            for bonus in [series.setBonus, series.groupBonus].compactMap({ $0 }) {
                pieceCount[bonus.skillId, default: 0] += 1
                let required = bonus.ranksByPieces.keys.min() ?? 0
                minPieces[bonus.skillId] = min(minPieces[bonus.skillId] ?? .max, required)
            }
        }
        if let weapon {
            for (skillId, level) in weapon.skills
            where master.skills[skillId]?.kind == .set || master.skills[skillId]?.kind == .group {
                pieceCount[skillId, default: 0] += level
            }
        }
        return pieceCount
            .filter { equipment.activeSkills[$0.key] == nil }
            .compactMap { skillId, count -> InactiveBonusRow? in
                guard let skill = master.skills[skillId] else { return nil }
                return InactiveBonusRow(
                    id: skillId, name: skill.name, kind: skill.kind,
                    currentPieces: count,
                    requiredPieces: minPieces[skillId] ?? 0,
                    contributors: contributors(of: skillId, kind: skill.kind))
            }
            .sorted {
                if $0.currentPieces != $1.currentPieces { return $0.currentPieces > $1.currentPieces }
                return $0.name < $1.name
            }
    }

    /// スキルに寄与している装備(武器→頭→胴→腕→腰→脚→護石の順)
    private func contributors(of skillId: SkillId, kind: SkillKind) -> [Contributor] {
        var found: Set<Contributor> = []
        if let weapon, weapon.skills[skillId] != nil { found.insert(.weapon) }
        for (pieceKind, piece) in equipment.pieces {
            if kind == .set || kind == .group {
                guard let series = master.armorSeries[piece.seriesId] else { continue }
                if [series.setBonus, series.groupBonus].compactMap({ $0 })
                    .contains(where: { $0.skillId == skillId }) {
                    found.insert(.piece(pieceKind))
                }
            } else if piece.skills[skillId] != nil {
                found.insert(.piece(pieceKind))
            }
        }
        if equipment.charm.skills[skillId] != nil { found.insert(.charm) }
        // 装飾品由来は装着先の装備に帰属させる
        for entry in equipment.decorations where entry.decoration.skills[skillId] != nil {
            switch entry.owner {
            case .weapon: found.insert(.weapon)
            case .armor(let pieceKind): found.insert(.piece(pieceKind))
            case .charmWeapon, .charmArmor: found.insert(.charm)
            }
        }
        var ordered: [Contributor] = []
        if found.contains(.weapon) { ordered.append(.weapon) }
        for pieceKind in ArmorPieceKind.allCases where found.contains(.piece(pieceKind)) {
            ordered.append(.piece(pieceKind))
        }
        if found.contains(.charm) { ordered.append(.charm) }
        return ordered
    }
}
