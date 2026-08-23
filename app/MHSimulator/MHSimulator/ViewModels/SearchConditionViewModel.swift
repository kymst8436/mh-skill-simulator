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
        if let weaponId = try? store.loadSelectedWeaponId() {
            selectedWeapon = master.weapons.first { $0.id == weaponId }
        }
    }

    /// 変更の都度AppStateへ保存(失敗しても操作は継続)
    private func persist() {
        try? dependencies.userStore.saveLastSearchConditions(
            conditions.map { (skillId: $0.id, level: $0.level) })
    }

    func selectWeapon(_ weapon: Weapon?) {
        selectedWeapon = weapon
        try? dependencies.userStore.saveSelectedWeaponId(weapon?.id)
    }

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
        SearchCondition(requiredSkills: Dictionary(
            uniqueKeysWithValues: conditions.map { ($0.id, $0.level) }))
    }
}
