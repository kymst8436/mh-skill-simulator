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
        MHFormat.requirementText(requirement, master: dependencies.master)
    }

    // MARK: - ウィッシュリスト(逆引き候補のワンタップ登録。2026-08-25追加)

    /// 登録済み要求(ボタンの状態表示用。画面表示時に読み込む)
    private(set) var wishlistRequirements: Set<CharmRules.Requirement> = []

    func loadWishlistRequirements() {
        let items = (try? dependencies.userStore.loadWishlist()) ?? []
        wishlistRequirements = Set(items.map(\.requirement))
    }

    func isInWishlist(_ requirement: CharmRules.Requirement) -> Bool {
        wishlistRequirements.contains(requirement)
    }

    /// 逆引き候補をウィッシュリストへ(重複登録は無視)
    func addToWishlist(_ requirement: CharmRules.Requirement) {
        guard !wishlistRequirements.contains(requirement) else { return }
        let item = WishlistItem(
            skills: requirement.skills
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { CharmRules.GroupEntry(skillId: $0.key, level: $0.value) },
            weaponSlots: requirement.weaponSlots,
            armorSlots: requirement.armorSlots)
        do {
            try dependencies.userStore.insertWishlistItem(item)
            wishlistRequirements.insert(requirement)
        } catch {
            // 保存失敗は状態を変えない(ボタンは押せるまま)
        }
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
