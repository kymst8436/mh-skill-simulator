import SwiftUI
import MHSimulatorCore

/// 装備比較②: 比較画面(画面設計4.17②)。対象装備→期待値→状態別(トグル)→アイテム・食事
struct EquipmentCompareResultView: View {
    typealias Side = EquipmentCompareViewModel.Side
    typealias Calc = ExpectedAttackCalculator

    @Environment(\.dismiss) private var dismiss
    let viewModel: EquipmentCompareViewModel
    @State private var pickerSide: PickerTarget?
    @FocusState private var focusedField: Field?

    private struct PickerTarget: Identifiable {
        let side: Side
        var id: String { side.rawValue }
    }

    private enum Field: Hashable {
        case manualAttack(Side), manualAffinity(Side), extraAttack, extraAffinity
    }

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MHSectionHeader(title: String(localized: "対象装備"))
                        .padding(.top, 20)
                    gearCard
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        .mhEntrance(0)

                    MHSectionHeader(title: String(localized: "期待値"))
                        .padding(.top, 20)
                    expectedCard
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        .mhEntrance(1)

                    MHSectionHeader(title: String(localized: "状態別"))
                        .padding(.top, 20)
                    stateCard
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        .mhEntrance(2)

                    notes
                        .mhEntrance(3)
                }
                .padding(.bottom, 24)
            }
        }
        .mhNavigationTitle(String(localized: "装備比較"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            MHBackButton { dismiss() }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "完了")) { focusedField = nil }
                    .foregroundStyle(Color.mhAccent)
            }
        }
        .sheet(item: $pickerSide) { target in
            SavedSetPickerSheet(viewModel: viewModel, side: target.side)
        }
        .confirmationDialog(
            viewModel.pendingExclusive.map(viewModel.exclusiveMessage) ?? String(),
            isPresented: Binding(
                get: { viewModel.pendingExclusive != nil },
                set: { if !$0 { viewModel.cancelExclusive() } }),
            titleVisibility: .visible
        ) {
            Button("OK") { viewModel.confirmExclusive() }
            Button("キャンセル", role: .cancel) { viewModel.cancelExclusive() }
        }
        .task { viewModel.load() }
    }

    // MARK: - 対象装備

    private var gearCard: some View {
        MHCard {
            HStack(alignment: .top, spacing: 0) {
                gearColumn(.base)
                columnDivider
                if viewModel.compare != nil {
                    gearColumn(.compare)
                } else {
                    placeholderColumn
                }
            }
        }
    }

    private var columnDivider: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(width: 1)
    }

    private func columnHeader(_ side: Side, showsChange: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(side == .base ? String(localized: "ベース") : String(localized: "比較"))
                .font(.system(size: 12))
                .tracking(1)
                .foregroundStyle(Color.mhTextTertiary)
            Spacer()
            if showsChange {
                Button {
                    pickerSide = PickerTarget(side: side)
                } label: {
                    Text("変更")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mhAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func gearColumn(_ side: Side) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(side, showsChange: true)
            Text(verbatim: viewModel.set(for: side)?.name ?? String())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.mhTextPrimary)
                .lineLimit(2)
                .padding(.bottom, 2)
            ForEach(viewModel.gearLines(for: side)) { line in
                HStack(spacing: 8) {
                    gearIcon(line.icon)
                        .frame(width: 20, height: 20)
                    Text(line.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let stats = viewModel.weaponStats(for: side), stats.isManual {
                manualWeaponFields(side)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private func gearIcon(_ icon: EquipmentCompareViewModel.GearLine.Icon) -> some View {
        switch icon {
        case .weapon(let name?):
            Image(name).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Color.mhTextSecondary)
        case .weapon(nil):
            Image(systemName: "circle.dashed")
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextSecondary)
        case .piece(let kind):
            Image(MHFormat.pieceIconName(kind)).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Color.mhTextSecondary)
        case .charm:
            Image(MHFormat.charmIconName).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Color.mhTextSecondary)
        }
    }

    /// 武器の攻撃力をマスタから引けない列の手入力(画面設計4.17 #5)
    private func manualWeaponFields(_ side: Side) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("武器の攻撃力を入力")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Color.mhTextTertiary)
                .padding(.top, 6)
            NumberField(
                label: String(localized: "基礎攻撃力"),
                value: viewModel.manualWeapon(for: side).attack,
                keyboard: .numberPad,
                focus: $focusedField, field: .manualAttack(side)
            ) { viewModel.commitManualAttack($0, for: side) }
            NumberField(
                label: String(localized: "会心率"),
                value: viewModel.manualWeapon(for: side).affinity,
                unit: "%", keyboard: .numbersAndPunctuation,
                focus: $focusedField, field: .manualAffinity(side)
            ) { viewModel.commitManualAffinity($0, for: side) }
        }
    }

    private var placeholderColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(.compare, showsChange: false)
            Button {
                pickerSide = PickerTarget(side: .compare)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                    Text("比較する装備構成を選択")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.mhAccent)
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - 期待値

    private var expectedCard: some View {
        MHCard {
            HStack(alignment: .top, spacing: 0) {
                expectedColumn(.base)
                columnDivider
                expectedColumn(.compare)
            }
        }
    }

    private func expectedColumn(_ side: Side) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("会心込み攻撃力")
                .font(.system(size: 12))
                .tracking(1)
                .foregroundStyle(Color.mhTextTertiary)
            if let output = viewModel.output(for: side) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(output.expected, format: .number.precision(.fractionLength(1)))
                        .font(MHFont.statNumber)
                        .foregroundStyle(Color.mhTextPrimary)
                        .contentTransition(.numericText())
                    if side == .compare, let diff = viewModel.diffPercent {
                        diffLabel(diff)
                    }
                }
                statRow(String(localized: "攻撃力"), "\(output.attack)")
                statRow(
                    String(localized: "会心率"),
                    output.isAffinityCapped
                        ? String(localized: "\(output.affinity)%(上限)")
                        : "\(output.affinity)%")
                statRow(String(localized: "会心倍率"), "×" + output.critMultiplier.formatted(.number.precision(.fractionLength(2))))
            } else {
                Text(verbatim: "—")
                    .font(MHFont.statNumber)
                    .foregroundStyle(Color.mhTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .animation(.default, value: viewModel.output(for: side)?.expected)
    }

    private func diffLabel(_ diff: Double) -> some View {
        let sign = diff > 0.05 ? "▲" : (diff < -0.05 ? "▼" : "±")
        let color: Color = diff > 0.05 ? .mhAccent : (diff < -0.05 ? .mhDestructive : .mhTextTertiary)
        let text = sign + (abs(diff) < 0.05 ? "0.0" : abs(diff).formatted(.number.precision(.fractionLength(1)))) + "%"
        return Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.mhTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.mhTextPrimary)
                .contentTransition(.numericText())
        }
    }

    // MARK: - 状態別

    private var stateCard: some View {
        MHCard {
            VStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    conditionRow(row)
                    separator
                }
                Text("アイテム・食事")
                    .font(.system(size: 12))
                    .tracking(1)
                    .foregroundStyle(Color.mhTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                toggleRow(String(localized: "力の護符"), isOn: Binding(
                    get: { viewModel.items.powercharm }, set: { viewModel.items.powercharm = $0 }))
                separator
                toggleRow(String(localized: "鬼人の粉塵"), isOn: Binding(
                    get: { viewModel.items.demonPowder }, set: { viewModel.items.demonPowder = $0 }))
                separator
                menuRow(String(localized: "鬼人薬"), selection: Binding(
                    get: { viewModel.items.demondrug }, set: { viewModel.items.demondrug = $0 }),
                    isNone: viewModel.items.demondrug == .none, label: demondrugLabel)
                separator
                menuRow(String(localized: "怪力の種・丸薬"), selection: Binding(
                    get: { viewModel.items.might }, set: { viewModel.items.might = $0 }),
                    isNone: viewModel.items.might == .none, label: mightLabel)
                separator
                menuRow(String(localized: "お食事ムラ気術"), selection: Binding(
                    get: { viewModel.items.moodyMeal }, set: { viewModel.items.moodyMeal = $0 }),
                    isNone: viewModel.items.moodyMeal == .none, label: moodyLabel)
                separator
                NumberField(
                    label: String(localized: "その他の攻撃力加算"),
                    value: viewModel.extraAttack, keyboard: .numberPad,
                    focus: $focusedField, field: .extraAttack, inCard: true
                ) { viewModel.commitExtraAttack($0) }
                separator
                NumberField(
                    label: String(localized: "その他の会心率加算"),
                    value: viewModel.extraAffinity, unit: "%", keyboard: .numbersAndPunctuation,
                    focus: $focusedField, field: .extraAffinity, inCard: true
                ) { viewModel.commitExtraAffinity($0) }
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    private func conditionRow(_ row: EquipmentCompareViewModel.ConditionRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                labelWithBadge(row.title, isOn: viewModel.isOn(row.condition))
                Text(viewModel.levelLine(row))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { viewModel.isOn(row.condition) },
                set: { _ in viewModel.toggle(row.condition) })) { EmptyView() }
                .labelsHidden()
                .tint(Color.mhAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }

    /// 「<名前> [発動中]」。バッジは名前の後ろに続け、長い言語では折り返す
    private func labelWithBadge(_ title: String, isOn: Bool) -> some View {
        MHFlowLayout(spacing: 6) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextPrimary)
            if isOn {
                activeBadge
            }
        }
    }

    private var activeBadge: some View {
        Text("発動中")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.mhAccentSoft)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.mhAccentWash)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            labelWithBadge(title, isOn: isOn.wrappedValue)
            Spacer(minLength: 8)
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .tint(Color.mhAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }

    /// 排他アイテムのプルダウン(項目名タップでメニュー)
    private func menuRow<T: Hashable & CaseIterable>(
        _ title: String, selection: Binding<T>, isNone: Bool, label: @escaping (T) -> String
    ) -> some View where T.AllCases: RandomAccessCollection {
        Menu {
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                Spacer(minLength: 8)
                MHFlowLayout(spacing: 6) {
                    Text(label(selection.wrappedValue))
                        .font(.system(size: 14))
                        .foregroundStyle(isNone ? Color.mhTextTertiary : Color.mhTextPrimary)
                    if !isNone { activeBadge }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
    }

    private func demondrugLabel(_ v: Calc.ItemSelection.Demondrug) -> String {
        switch v {
        case .none: String(localized: "なし")
        case .normal: String(localized: "鬼人薬")
        case .mega: String(localized: "鬼人薬グレート")
        }
    }

    private func mightLabel(_ v: Calc.ItemSelection.Might) -> String {
        switch v {
        case .none: String(localized: "なし")
        case .seed: String(localized: "怪力の種")
        case .pill: String(localized: "怪力の丸薬")
        }
    }

    private func moodyLabel(_ v: Calc.ItemSelection.MoodyMeal) -> String {
        switch v {
        case .none: String(localized: "なし")
        case .small: String(localized: "お食事ムラ気術【小】")
        case .large: String(localized: "お食事ムラ気術【大】")
        }
    }

    // MARK: - 注記

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("装衣・狩猟笛・未計上スキルの分は「その他」に入れる")
            if let note = viewModel.uncountedNote {
                Text(note)
            }
            Text("物理のみ。属性・斬れ味・肉質・モーション値は比較に影響しないため含めていません")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.mhTextTertiary)
        .padding(.horizontal, 32)
        .padding(.top, 10)
    }

    // MARK: - 数値入力

    /// 数値TextField(画面設計4.17 規約から外れる点: 枠なし・右寄せ)
    private struct NumberField: View {
        let label: String
        let value: Int
        var unit: String? = nil
        let keyboard: UIKeyboardType
        let focus: FocusState<Field?>.Binding
        let field: Field
        var inCard = false
        let onCommit: (String) -> Void
        @State private var text = ""

        var body: some View {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: inCard ? 15 : 13))
                    .foregroundStyle(Color.mhTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                TextField(text: $text) { EmptyView() }
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mhTextPrimary)
                    .frame(minWidth: 56, maxWidth: 80)
                    .focused(focus, equals: field)
                    .onSubmit { onCommit(text) }
                if let unit {
                    Text(unit)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhTextSecondary)
                }
            }
            .padding(.horizontal, inCard ? 16 : 0)
            .frame(minHeight: inCard ? 48 : 36)
            .onAppear { text = String(value) }
            .onChange(of: value) { _, newValue in
                if focus.wrappedValue != field { text = String(newValue) }
            }
            .onChange(of: focus.wrappedValue) { old, new in
                if old == field, new != field { onCommit(text) }
            }
        }
    }
}
