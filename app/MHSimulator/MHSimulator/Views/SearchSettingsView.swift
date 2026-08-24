import SwiftUI
import MHSimulatorCore

/// 検索設定sheet(画面設計4.10。2026-08-24追加)。
/// 装備の固定(必ず使う)・除外(使わない)を指定する。OKで反映、スワイプ閉じで破棄
struct SearchSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let conditionViewModel: SearchConditionViewModel
    @State private var filters: EquipmentFilters
    @State private var pickerTarget: PickerTarget?

    private var master: MasterDatabase { conditionViewModel.dependencies.master }

    init(conditionViewModel: SearchConditionViewModel) {
        self.conditionViewModel = conditionViewModel
        _filters = State(initialValue: conditionViewModel.equipmentFilters)
    }

    private enum PickerTarget: Identifiable {
        case pinPiece(ArmorPieceKind)
        case excludePiece
        case pinCharm
        case excludeCharm

        var id: String {
            switch self {
            case .pinPiece(let kind): "pin-\(kind.rawValue)"
            case .excludePiece: "exclude-piece"
            case .pinCharm: "pin-charm"
            case .excludeCharm: "exclude-charm"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .mhEntrance(0)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        MHSectionHeader(title: "固定(必ず使う)")
                            .padding(.top, 4)
                        MHCard {
                            VStack(spacing: 0) {
                                ForEach(ArmorPieceKind.allCases, id: \.self) { kind in
                                    pinPieceRow(kind)
                                    separator
                                }
                                pinCharmRow
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    }
                    .mhEntrance(1)

                    Group {
                        MHSectionHeader(title: "除外(使わない)")
                            .padding(.top, 20)
                        MHCard {
                            VStack(spacing: 0) {
                                ForEach(filters.excludedPieces, id: \.self) { pieceId in
                                    excludedPieceRow(pieceId)
                                    separator
                                }
                                ForEach(filters.excludedCharmIds, id: \.self) { charmId in
                                    excludedCharmRow(charmId)
                                    separator
                                }
                                addRow("防具を除外に追加") { pickerTarget = .excludePiece }
                                separator
                                addRow("生産護石を除外に追加") { pickerTarget = .excludeCharm }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    }
                    .mhEntrance(2)
                }
                .padding(.bottom, 24)
            }
            okButtonBar
                .mhEntrance(3)
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
        .sheet(item: $pickerTarget) { target in
            picker(for: target)
        }
    }

    private var header: some View {
        HStack {
            Text("検索設定")
                .font(MHFont.screenTitle)
                .tracking(1.5)
                .foregroundStyle(Color.mhTitleGold)
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var okButtonBar: some View {
        MHPrimaryButton(title: "OK") {
            conditionViewModel.applyEquipmentFilters(filters)
            dismiss()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mhBackgroundElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairlineFaint).frame(height: 1)
        }
    }

    // MARK: - 行

    private func pinPieceRow(_ kind: ArmorPieceKind) -> some View {
        Button {
            pickerTarget = .pinPiece(kind)
        } label: {
            HStack(spacing: 10) {
                Image(MHFormat.pieceIconName(kind))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text(MHFormat.pieceLabel(kind))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                    .frame(width: 24, alignment: .leading)
                if let id = filters.pinnedPieceId(for: kind),
                   let piece = master.armorPieces.first(where: { $0.id == id }) {
                    Text(piece.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                        .lineLimit(1)
                } else {
                    Text("指定なし")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private var pinCharmRow: some View {
        Button {
            pickerTarget = .pinCharm
        } label: {
            HStack(spacing: 10) {
                Image(MHFormat.charmIconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("護石")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                    .frame(width: 24, alignment: .leading)
                if let id = filters.pinnedCharmId, let charm = fixedCharm(id) {
                    Text(charm.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                        .lineLimit(1)
                } else {
                    Text("指定なし")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private func excludedPieceRow(_ pieceId: Int64) -> some View {
        HStack(spacing: 10) {
            if let piece = master.armorPieces.first(where: { $0.id == pieceId }) {
                Image(MHFormat.pieceIconName(piece.kind))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text(piece.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextPrimary)
                    .lineLimit(1)
            } else {
                Text("不明な防具")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            Spacer()
            Button {
                filters.excludedPieces.removeAll { $0 == pieceId }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.mhDestructive)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private func excludedCharmRow(_ charmId: Int32) -> some View {
        HStack(spacing: 10) {
            Image(MHFormat.charmIconName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text(fixedCharm(charmId)?.name ?? "不明な護石")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextPrimary)
                .lineLimit(1)
            Spacer()
            Button {
                filters.excludedCharmIds.removeAll { $0 == charmId }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.mhDestructive)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 16))
                Spacer()
            }
            .foregroundStyle(Color.mhAccent)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    private func fixedCharm(_ id: Int32) -> Charm? {
        master.fixedCharms.first { charm in
            if case .fixed(let charmId, _) = charm.source { return charmId == id }
            return false
        }
    }

    // MARK: - ピッカー

    @ViewBuilder
    private func picker(for target: PickerTarget) -> some View {
        switch target {
        case .pinPiece(let kind):
            ArmorPiecePickerView(
                master: master,
                mode: .pin(kind),
                selectedId: filters.pinnedPieceId(for: kind),
                excludedIds: []
            ) { pieceId in
                filters.setPinnedPiece(pieceId, for: kind)
            }
        case .excludePiece:
            ArmorPiecePickerView(
                master: master,
                mode: .exclude,
                selectedId: nil,
                excludedIds: Set(filters.excludedPieces)
            ) { pieceId in
                if let pieceId {
                    if filters.excludedPieces.contains(pieceId) {
                        filters.excludedPieces.removeAll { $0 == pieceId }
                    } else {
                        filters.addExcludedPiece(pieceId)
                    }
                }
            }
        case .pinCharm:
            FixedCharmPickerView(
                master: master,
                mode: .pin,
                selectedId: filters.pinnedCharmId,
                excludedIds: []
            ) { charmId in
                filters.setPinnedCharm(charmId)
            }
        case .excludeCharm:
            FixedCharmPickerView(
                master: master,
                mode: .exclude,
                selectedId: nil,
                excludedIds: Set(filters.excludedCharmIds)
            ) { charmId in
                if let charmId {
                    if filters.excludedCharmIds.contains(charmId) {
                        filters.excludedCharmIds.removeAll { $0 == charmId }
                    } else {
                        filters.addExcludedCharm(charmId)
                    }
                }
            }
        }
    }
}

// MARK: - 防具ピッカー

/// 防具選択sheet(検索設定用)。pin=単一選択で即閉じ / exclude=タップでトグル(連続追加)
private struct ArmorPiecePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let master: MasterDatabase
    let mode: Mode
    let selectedId: Int64?
    let excludedIds: Set<Int64>
    let onSelect: (Int64?) -> Void

    @State private var searchText = ""
    @State private var kindFilter: ArmorPieceKind

    enum Mode {
        case pin(ArmorPieceKind)
        case exclude
    }

    init(master: MasterDatabase, mode: Mode, selectedId: Int64?, excludedIds: Set<Int64>, onSelect: @escaping (Int64?) -> Void) {
        self.master = master
        self.mode = mode
        self.selectedId = selectedId
        self.excludedIds = excludedIds
        self.onSelect = onSelect
        if case .pin(let kind) = mode {
            _kindFilter = State(initialValue: kind)
        } else {
            _kindFilter = State(initialValue: .head)
        }
    }

    private var isPin: Bool {
        if case .pin = mode { return true }
        return false
    }

    private var visiblePieces: [ArmorPiece] {
        master.armorPieces
            .filter { $0.kind == kindFilter && $0.name.mhContains(searchText) }
            .sorted {
                guard let s0 = master.armorSeries[$0.seriesId],
                      let s1 = master.armorSeries[$1.seriesId] else { return $0.name < $1.name }
                if s0.rarity != s1.rarity { return s0.rarity > s1.rarity }
                return $0.name.compare($1.name, locale: Locale(identifier: "ja_JP")) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader(title: isPin ? "固定する防具" : "除外する防具", showsDone: !isPin) { dismiss() }
            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            if !isPin {
                kindFilterBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            Rectangle().fill(Color.mhHairline).frame(height: 1)
            pieceList
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
    }

    private var kindFilterBar: some View {
        HStack(spacing: 2) {
            ForEach(ArmorPieceKind.allCases, id: \.self) { kind in
                let isSelected = kindFilter == kind
                Button {
                    kindFilter = kind
                } label: {
                    Text(MHFormat.pieceLabel(kind))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.mhTextPrimary : Color.mhTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(isSelected ? Color.mhHairline : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .padding(2)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextTertiary)
            TextField("", text: $searchText,
                      prompt: Text("防具名で検索").foregroundStyle(Color.mhTextTertiary))
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextPrimary)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
    }

    private var pieceList: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isPin {
                        clearRow
                        rowSeparator
                    }
                    ForEach(visiblePieces, id: \.id) { piece in
                        pieceRow(piece)
                        rowSeparator
                    }
                }
            }
        }
    }

    private var clearRow: some View {
        Button {
            onSelect(nil)
            dismiss()
        } label: {
            HStack {
                Text("指定なし")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextSecondary)
                Spacer()
                if selectedId == nil {
                    checkmark
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private func pieceRow(_ piece: ArmorPiece) -> some View {
        let isMarked = isPin ? (selectedId == piece.id) : excludedIds.contains(piece.id)
        return Button {
            if isPin {
                onSelect(piece.id)
                dismiss()
            } else {
                onSelect(piece.id)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mhTextPrimary)
                    let summary = skillSummary(piece)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mhTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let series = master.armorSeries[piece.seriesId] {
                    RarityBadge(rarity: series.rarity)
                }
                Text(MHFormat.slotSymbols(piece.slots))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mhTextSecondary)
                if isMarked {
                    checkmark
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(isMarked ? Color.mhAccentWash : .clear)
        }
    }

    private func skillSummary(_ piece: ArmorPiece) -> String {
        piece.skills
            .compactMap { id, level in
                guard let skill = master.skills[id], skill.kind == .armor || skill.kind == .weapon
                else { return nil }
                return MHFormat.skillLine(skill.name, level)
            }
            .sorted()
            .joined(separator: "・")
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.mhAccent)
    }

    private var rowSeparator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }
}

/// sheet共通のヘッダ(タイトル+OK)
private func pickerHeader(title: String, showsDone: Bool, onDone: @escaping () -> Void) -> some View {
    HStack {
        Color.clear.frame(width: 60, height: 1)
        Spacer()
        Text(title)
            .font(MHFont.screenTitle)
            .tracking(1.5)
            .foregroundStyle(Color.mhTitleGold)
        Spacer()
        if showsDone {
            Button("OK", action: onDone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mhAccent)
                .frame(width: 60, alignment: .trailing)
        } else {
            Color.clear.frame(width: 60, height: 1)
        }
    }
    .padding(.horizontal, 16)
    .padding(.top, 18)
    .padding(.bottom, 12)
}

// MARK: - 生産護石ピッカー

/// 生産護石選択sheet(検索設定用)。pin=単一選択で即閉じ / exclude=タップでトグル
private struct FixedCharmPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let master: MasterDatabase
    let mode: Mode
    let selectedId: Int32?
    let excludedIds: Set<Int32>
    let onSelect: (Int32?) -> Void

    @State private var searchText = ""

    enum Mode { case pin, exclude }

    private var isPin: Bool { mode == .pin }

    private var visibleCharms: [(id: Int32, charm: Charm)] {
        master.fixedCharms
            .compactMap { charm -> (Int32, Charm)? in
                guard case .fixed(let id, _) = charm.source else { return nil }
                guard charm.name.mhContains(searchText) else { return nil }
                return (id, charm)
            }
            .sorted { $0.1.name.compare($1.1.name, locale: Locale(identifier: "ja_JP")) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader(title: isPin ? "固定する護石" : "除外する護石", showsDone: !isPin) { dismiss() }
            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Rectangle().fill(Color.mhHairline).frame(height: 1)
            charmList
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextTertiary)
            TextField("", text: $searchText,
                      prompt: Text("護石名で検索").foregroundStyle(Color.mhTextTertiary))
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextPrimary)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
    }

    private var charmList: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isPin {
                        clearRow
                        rowSeparator
                    }
                    ForEach(visibleCharms, id: \.id) { entry in
                        charmRow(entry.id, entry.charm)
                        rowSeparator
                    }
                }
            }
        }
    }

    private var clearRow: some View {
        Button {
            onSelect(nil)
            dismiss()
        } label: {
            HStack {
                Text("指定なし")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextSecondary)
                Spacer()
                if selectedId == nil { checkmark }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
    }

    private func charmRow(_ id: Int32, _ charm: Charm) -> some View {
        let isMarked = isPin ? (selectedId == id) : excludedIds.contains(id)
        let summary = charm.skills
            .compactMap { skillId, level in
                master.skills[skillId].map { MHFormat.skillLine($0.name, level) }
            }
            .sorted()
            .joined(separator: "・")
        return Button {
            if isPin {
                onSelect(id)
                dismiss()
            } else {
                onSelect(id)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(charm.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mhTextPrimary)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mhTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isMarked { checkmark }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(isMarked ? Color.mhAccentWash : .clear)
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.mhAccent)
    }

    private var rowSeparator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }
}
