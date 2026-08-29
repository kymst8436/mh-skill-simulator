import Foundation
import Observation
import MHSimulatorCore

/// 追加スキルsheet(画面設計4.12)。表示時に判定を開始し、完了まで実行する。
/// 時間予算は課さない(スキル単位の進捗表示があり、待てる/やめるはユーザーが選べるため。2026-08-26決定)。
/// sheetを閉じると協調キャンセルで中断し、途中結果は破棄される
@Observable
final class AdditionalSkillsViewModel {
    enum Phase {
        case judging
        case list
        case empty
        case failed
    }

    private let dependencies: AppDependencies
    /// スキル詳細sheet(4.14)がマスタ参照に使う
    var master: MasterDatabase { dependencies.master }
    private let condition: SearchCondition
    private let weapon: Weapon?
    /// 行タップ時に呼ぶ(SearchResultsViewModel.addSkillAndRetry)
    private let onAdd: (SkillId, Int) -> Void

    private(set) var phase: Phase = .judging
    private(set) var entries: [AdditionalSkillFinder.Entry] = []
    private(set) var determinedCount = 0
    private(set) var targetCount = 0

    private var task: Task<Void, Never>?
    private var cancelDetachedWork: [() -> Void] = []
    private var hasStarted = false

    init(
        dependencies: AppDependencies,
        condition: SearchCondition,
        weapon: Weapon?,
        onAdd: @escaping (SkillId, Int) -> Void
    ) {
        self.dependencies = dependencies
        self.condition = condition
        self.weapon = weapon
        self.onAdd = onAdd
    }

    /// スキル行の表示名(kind=set/groupは接尾辞付き。画面設計4.12構成要素5)
    func skillLabel(_ id: SkillId) -> String {
        guard let skill = dependencies.master.skills[id] else { return "?" }
        switch skill.kind {
        case .set: return skill.name + String(localized: "(シリーズ)")
        case .group: return skill.name + String(localized: "(グループ)")
        case .armor, .weapon: return skill.name
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        run()
    }

    func retry() {
        cancel()
        task = nil
        entries = []
        phase = .judging
        run()
    }

    func cancel() {
        task?.cancel()
        cancelDetachedWork.forEach { $0() }
        cancelDetachedWork.removeAll()
    }

    func select(_ entry: AdditionalSkillFinder.Entry) {
        onAdd(entry.skillId, entry.maxAddableLevel)
    }

    private func run() {
        let finder = dependencies.additionalSkillFinder
        let condition = condition
        let weapon = weapon
        let ownedCharms = dependencies.loadOwnedCharmsForSearch()
        task = Task {
            do {
                let work = Task.detached(priority: .userInitiated) {
                    try finder.find(
                        condition: condition, weapon: weapon, ownedCharms: ownedCharms,
                        onSkillDetermined: { [weak self] determined, total in
                            Task { @MainActor [weak self] in
                                self?.determinedCount = determined
                                self?.targetCount = total
                            }
                        })
                }
                cancelDetachedWork.append { work.cancel() }
                let outcome = try await work.value
                guard !Task.isCancelled else { return }
                entries = outcome.entries
                determinedCount = outcome.determinedCount
                targetCount = outcome.targetCount
                phase = outcome.entries.isEmpty ? .empty : .list
                task = nil
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
                task = nil
            }
        }
    }
}
