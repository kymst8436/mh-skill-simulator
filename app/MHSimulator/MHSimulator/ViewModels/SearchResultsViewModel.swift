import Foundation
import Observation
import MHSimulatorCore

/// 検索結果画面(画面設計4.4)。検索実行→0件時は逆引きを自動実行(仕様3.1手順7)
@Observable
final class SearchResultsViewModel {
    enum Phase {
        case searching
        case results(SearchResult)
        case reverseSearching       // 0件確定、逆引き計算中
        case reverse(CharmOracle.Outcome)
        case failed
    }

    private let dependencies: AppDependencies
    private let conditionViewModel: SearchConditionViewModel
    private(set) var phase: Phase = .searching
    private(set) var condition: SearchCondition
    private let weapon: Weapon?
    private var task: Task<Void, Never>?
    /// detached探索タスクの中断用(detachedは親のキャンセルを継承しないため明示的に伝える)
    private var cancelDetachedWork: [() -> Void] = []

    init(dependencies: AppDependencies, conditionViewModel: SearchConditionViewModel) {
        self.dependencies = dependencies
        self.conditionViewModel = conditionViewModel
        self.condition = conditionViewModel.makeCondition()
        self.weapon = conditionViewModel.selectedWeapon
    }

    func skillName(_ id: SkillId) -> String {
        dependencies.master.skills[id]?.name ?? "?"
    }

    func isConditionSkill(_ id: SkillId) -> Bool {
        condition.requiredSkills[id] != nil
    }

    /// 逆引き要求の表示文字列(例「攻撃Lv3 + 防具スロ①」)
    func requirementText(_ requirement: CharmRules.Requirement) -> String {
        var parts = requirement.skills
            .map { (skillName($0.key), $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { MHFormat.skillLine($0.0, $0.1) }
        parts += requirement.armorSlots.sorted(by: >).map { "防具スロ" + MHFormat.slotSymbols([$0]) }
        parts += requirement.weaponSlots.sorted(by: >).map { "武器スロ" + MHFormat.slotSymbols([$0]) }
        return parts.joined(separator: " + ")
    }

    func start() {
        guard task == nil else { return }
        runSearch()
    }

    func retry() {
        cancel()
        task = nil
        phase = .searching
        runSearch()
    }

    func cancel() {
        task?.cancel()
        cancelDetachedWork.forEach { $0() }
        cancelDetachedWork.removeAll()
    }

    /// 代替候補タップ: 条件からスキルを外して再検索(条件画面側にも反映)
    func removeSkillAndRetry(_ id: SkillId) {
        conditionViewModel.removeSkill(id)
        condition = conditionViewModel.makeCondition()
        retry()
    }

    /// 護石登録後の再検索(逆引き候補→登録→自動で組み直す)
    func reloadAndRetry() {
        retry()
    }

    private func runSearch() {
        let engine = dependencies.engine
        let oracle = dependencies.oracle
        let condition = condition
        let weapon = weapon
        let ownedCharms = dependencies.loadOwnedCharmsForSearch()
        task = Task {
            do {
                let options = SearchEngine.Options(maxResults: 100, deadline: Date().addingTimeInterval(5))
                let searchWork = Task.detached(priority: .userInitiated) {
                    try engine.search(condition: condition, weapon: weapon, ownedCharms: ownedCharms, options: options)
                }
                cancelDetachedWork.append { searchWork.cancel() }
                let result = try await searchWork.value
                guard !Task.isCancelled else { return }
                if result.sets.isEmpty {
                    phase = .reverseSearching
                    let outcomeOptions = CharmOracle.Options(deadline: Date().addingTimeInterval(4))
                    let oracleWork = Task.detached(priority: .userInitiated) {
                        try oracle.reverseLookup(
                            condition: condition, weapon: weapon,
                            ownedCharms: ownedCharms, options: outcomeOptions)
                    }
                    cancelDetachedWork.append { oracleWork.cancel() }
                    let outcome = try await oracleWork.value
                    guard !Task.isCancelled else { return }
                    phase = .reverse(outcome)
                } else {
                    phase = .results(result)
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
            }
        }
    }
}
