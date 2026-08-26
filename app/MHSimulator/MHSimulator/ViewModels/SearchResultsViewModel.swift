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

    /// 同一入力での再試行: 探索は決定的で同じ場所で時間切れになるため、予算を延長して再実行する(2026-08-26)
    func retry() {
        retryAttempt = min(retryAttempt + 1, StageBudget.maxRetryAttempt)
        restart()
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
        retryAttempt = 0  // 入力が変わったので基準予算に戻す
        restart()
    }

    /// 護石登録後の再検索(逆引き候補→登録→自動で組み直す)
    func reloadAndRetry() {
        retryAttempt = 0  // 護石追加で入力が変わったので基準予算に戻す
        restart()
    }

    private func restart() {
        cancel()
        task = nil
        phase = .searching
        runSearch()
    }

    /// ステージ別の時間予算(検索/逆引きで独立。設計判断2026-08-26)。
    /// 再試行ごとに2倍(検索5→10→20秒、逆引き4→8→16秒。上限4倍)
    private enum StageBudget {
        static let searchSeconds = 5
        static let reverseLookupSeconds = 4
        static let maxRetryAttempt = 2
    }

    /// 再試行回数(予算延長用。入力が変わる再検索でリセット)
    private var retryAttempt = 0

    private func stageBudget(baseSeconds: Int) -> Duration {
        .seconds(baseSeconds << retryAttempt)
    }

    /// 1ステージをdetachedで実行し、時間予算超過でタスクをキャンセルする。
    /// コア側は協調キャンセルで途中結果を返すため、超過時も部分結果が得られる
    private func runStage<T: Sendable>(
        budget: Duration, _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let stage = Task.detached(priority: .userInitiated) { try work() }
        cancelDetachedWork.append { stage.cancel() }
        let timer = Task {
            try? await Task.sleep(for: budget)
            stage.cancel()
        }
        defer { timer.cancel() }
        return try await stage.value
    }

    private func runSearch() {
        let engine = dependencies.engine
        let oracle = dependencies.oracle
        let condition = condition
        let weapon = weapon
        let ownedCharms = dependencies.loadOwnedCharmsForSearch()
        task = Task {
            do {
                let result = try await runStage(budget: stageBudget(baseSeconds: StageBudget.searchSeconds)) {
                    try engine.search(
                        condition: condition, weapon: weapon, ownedCharms: ownedCharms,
                        options: SearchEngine.Options(maxResults: 100))
                }
                guard !Task.isCancelled else { return }
                if result.sets.isEmpty {
                    phase = .reverseSearching
                    let outcome = try await runStage(budget: stageBudget(baseSeconds: StageBudget.reverseLookupSeconds)) {
                        try oracle.reverseLookup(
                            condition: condition, weapon: weapon, ownedCharms: ownedCharms)
                    }
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
