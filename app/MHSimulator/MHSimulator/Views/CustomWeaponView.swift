import SwiftUI
import MHSimulatorCore

/// カスタム武器(アーティア)設定フォーム(仕様3.1 2026-08-24改訂)。
/// 武器選択画面の「アーティア」チップ選択時にインライン表示される。
/// TU追加武器(巨撃アーティア等)がデータ未収録の間、スロットと
/// シリーズ/グループスキルを手動で仮定して検索に反映する
struct CustomWeaponForm: View {
    let conditionViewModel: SearchConditionViewModel
    /// 「この構成で設定」確定時に呼ばれる(親が画面を閉じる)
    let onApplied: () -> Void
    @State private var config: CustomWeaponConfig

    private var master: MasterDatabase { conditionViewModel.dependencies.master }

    init(conditionViewModel: SearchConditionViewModel, onApplied: @escaping () -> Void) {
        self.conditionViewModel = conditionViewModel
        self.onApplied = onApplied
        _config = State(initialValue: conditionViewModel.customWeaponConfig ?? CustomWeaponConfig())
    }

    private var setSkills: [Skill] {
        master.skills.values.filter { $0.kind == .set }
            .sorted { $0.name.compare($1.name, locale: Locale(identifier: "ja_JP")) == .orderedAscending }
    }

    private var groupSkills: [Skill] {
        master.skills.values.filter { $0.kind == .group }
            .sorted { $0.name.compare($1.name, locale: Locale(identifier: "ja_JP")) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            scrollContent
            applyButtonBar
                .mhEntrance(4)
        }
    }

    /// 下部固定の設定ボタン(検索するボタンと同様。2026-08-24改訂)
    private var applyButtonBar: some View {
        MHPrimaryButton(title: "この構成で設定", isEnabled: hasContent) {
            conditionViewModel.selectCustomWeapon(config)
            onApplied()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mhBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairlineFaint).frame(height: 1)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 入場モーション: 武器選択画面のチップ(0)に続きセクション順(DESIGN.md §7.5)
                Group {
                    MHSectionHeader(title: "スロット")
                        .padding(.top, 4)
                    MHCard {
                        VStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { index in
                                slotRow(index)
                                if index < 2 { separator }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                .mhEntrance(1)

                Group {
                    MHSectionHeader(title: "シリーズスキル(1部位分として加算)")
                        .padding(.top, 20)
                    MHCard {
                        skillMenuRow(
                            selection: config.setSkillId,
                            skills: setSkills) { config.setSkillId = $0 }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                .mhEntrance(2)

                Group {
                    MHSectionHeader(title: "グループスキル(1部位分として加算)")
                        .padding(.top, 20)
                    MHCard {
                        skillMenuRow(
                            selection: config.groupSkillId,
                            skills: groupSkills) { config.groupSkillId = $0 }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Text("巨撃アーティア等、データ未収録の武器を仮定するための機能です")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mhTextTertiary)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                }
                .mhEntrance(3)
            }
            .padding(.bottom, 24)
        }
    }

    private var hasContent: Bool {
        config.slots.contains { $0 > 0 } || config.setSkillId != nil || config.groupSkillId != nil
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    private func slotRow(_ index: Int) -> some View {
        HStack {
            Text("スロット\(index + 1)")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextPrimary)
            Spacer()
            Menu {
                Button("なし") { config.slots[index] = 0 }
                ForEach(1...3, id: \.self) { size in
                    Button(MHFormat.slotSymbols([size])) { config.slots[index] = size }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(config.slots[index] == 0 ? "なし" : MHFormat.slotSymbols([config.slots[index]]))
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mhAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.mhAccent)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private func skillMenuRow(
        selection: SkillId?,
        skills: [Skill],
        onSelect: @escaping (SkillId?) -> Void
    ) -> some View {
        HStack {
            Text(selection.flatMap { master.skills[$0]?.name } ?? "(なし)")
                .font(.system(size: 16))
                .foregroundStyle(selection == nil ? Color.mhTextTertiary : Color.mhTextPrimary)
            Spacer()
            Menu {
                Button("(なし)") { onSelect(nil) }
                ForEach(skills, id: \.id) { skill in
                    Button(skill.name) { onSelect(skill.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("選択")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mhAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.mhAccent)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }
}
