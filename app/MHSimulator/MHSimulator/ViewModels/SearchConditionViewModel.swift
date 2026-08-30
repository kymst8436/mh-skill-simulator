import Foundation
import Observation
import MHSimulatorCore

/// 検索条件画面(画面設計4.1)。条件スキルの追加・削除・レベル調整
@Observable
final class SearchConditionViewModel {
    struct ConditionRow: Identifiable {
        let skill: Skill
        var level: Int
        var id: SkillId { skill.id }
    }

    let dependencies: AppDependencies
    private(set) var conditions: [ConditionRow] = []
    private(set) var selectedWeapon: Weapon?
    private(set) var customWeaponConfig: CustomWeaponConfig?
    /// 装備の固定・除外設定(検索設定画面。画面設計4.10)
    private(set) var equipmentFilters = EquipmentFilters()

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        restore()
    }

    /// AppStateから前回条件・前回武器を復元(仕様4.3 / 画面設計4.1 初期状態)
    private func restore() {
        let store = dependencies.userStore
        let master = dependencies.master
        if let saved = try? store.loadLastSearchConditions() {
            conditions = saved.compactMap { entry in
                guard let skill = master.skills[entry.skillId] else { return nil }
                return ConditionRow(skill: skill, level: min(entry.level, skill.maxLevel))
            }
        }
        if let json = (try? store.loadCustomWeaponJSON()) ?? nil,
           let config = CustomWeaponConfig.decode(json) {
            customWeaponConfig = config
            selectedWeapon = config.makeWeapon()
        } else if let weaponId = try? store.loadSelectedWeaponId() {
            selectedWeapon = master.weapons.first { $0.id == weaponId }
        }
        if let json = (try? store.loadSearchFiltersJSON()) ?? nil,
           let filters = EquipmentFilters.decode(json) {
            equipmentFilters = filters
        }
    }

    /// 変更の都度AppStateへ保存(失敗しても操作は継続)
    private func persist() {
        try? dependencies.userStore.saveLastSearchConditions(
            conditions.map { (skillId: $0.id, level: $0.level) })
    }

    func selectWeapon(_ weapon: Weapon?) {
        selectedWeapon = weapon
        customWeaponConfig = nil
        try? dependencies.userStore.saveSelectedWeaponId(weapon?.id)
        try? dependencies.userStore.saveCustomWeaponJSON(nil)
    }

    func selectCustomWeapon(_ config: CustomWeaponConfig) {
        customWeaponConfig = config
        selectedWeapon = config.makeWeapon()
        try? dependencies.userStore.saveSelectedWeaponId(nil)
        try? dependencies.userStore.saveCustomWeaponJSON(config.encoded())
    }

    /// 検索設定画面のOKで反映(永続化込み)
    func applyEquipmentFilters(_ filters: EquipmentFilters) {
        equipmentFilters = filters
        try? dependencies.userStore.saveSearchFiltersJSON(filters.isEmpty ? nil : filters.encoded())
    }

    var hasEquipmentFilters: Bool { !equipmentFilters.isEmpty }

    var canSearch: Bool { !conditions.isEmpty }
    var canReset: Bool { !conditions.isEmpty || selectedWeapon != nil }
    var selectedSkillIds: Set<SkillId> { Set(conditions.map(\.id)) }

    /// 追加(既存スキルなら最大レベルに更新=仕様3.1の後勝ち統合)。追加時は最大レベル(2026-08-23決定)
    func toggleSkill(_ skill: Skill) {
        if let index = conditions.firstIndex(where: { $0.id == skill.id }) {
            conditions.remove(at: index)
        } else {
            conditions.append(ConditionRow(skill: skill, level: skill.maxLevel))
        }
        persist()
    }

    func removeSkill(_ id: SkillId) {
        conditions.removeAll { $0.id == id }
        persist()
    }

    /// 追加スキル検索(F-9=画面設計4.12)からの反映: レベル指定で追加(既存スキルは後勝ちでレベル更新=仕様3.1)
    func addSkill(_ id: SkillId, level: Int) {
        guard let skill = dependencies.master.skills[id] else { return }
        let clamped = min(max(1, level), skill.maxLevel)
        if let index = conditions.firstIndex(where: { $0.id == id }) {
            conditions[index].level = clamped
        } else {
            conditions.append(ConditionRow(skill: skill, level: clamped))
        }
        persist()
    }

    func setLevel(_ id: SkillId, _ level: Int) {
        guard let index = conditions.firstIndex(where: { $0.id == id }) else { return }
        conditions[index].level = min(max(1, level), conditions[index].skill.maxLevel)
        persist()
    }

    func reset() {
        conditions.removeAll()
        selectWeapon(nil)
        persist()
    }

    func makeCondition() -> SearchCondition {
        SearchCondition(
            requiredSkills: Dictionary(
                uniqueKeysWithValues: conditions.map { ($0.id, $0.level) }),
            pinnedPieceIds: equipmentFilters.pinnedPieceIdsByKind,
            excludedPieceIds: Set(equipmentFilters.excludedPieces),
            pinnedFixedCharmId: equipmentFilters.pinnedCharmId,
            excludedFixedCharmIds: Set(equipmentFilters.excludedCharmIds),
            excludedDecorationIds: Set(equipmentFilters.excludedDecorations),
            considerLimitBreak: equipmentFilters.considerLimitBreak)
    }
}
