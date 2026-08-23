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
    var selectedWeapon: Weapon?  // Phase 4-3で武器選択画面から設定

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
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
    }

    func removeSkill(_ id: SkillId) {
        conditions.removeAll { $0.id == id }
    }

    func setLevel(_ id: SkillId, _ level: Int) {
        guard let index = conditions.firstIndex(where: { $0.id == id }) else { return }
        conditions[index].level = min(max(1, level), conditions[index].skill.maxLevel)
    }

    func reset() {
        conditions.removeAll()
        selectedWeapon = nil
    }

    func makeCondition() -> SearchCondition {
        SearchCondition(requiredSkills: Dictionary(
            uniqueKeysWithValues: conditions.map { ($0.id, $0.level) }))
    }
}
