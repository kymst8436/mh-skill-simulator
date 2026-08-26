import Foundation
import Observation
import MHSimulatorCore

/// 追加スキルsheet(画面設計4.12)。表示時に判定を開始し、時間予算8秒(仕様Q-15)で打ち切る。
/// F-2と異なりスキル単位で再開できるため、予算延長ではなく「続きを探す」(チェックポイント再開)を採る
@Observable
final class AdditionalSkillsViewModel {
    enum Phase {
        case judging
        case list
        case empty
        case failed
    }

    private let dependencies: AppDependencies
    private let condition: SearchCondition
    private let weapon: Weapon?
    /// 行タップ時に呼ぶ(SearchResultsViewModel.addSkillAndRetry)
    private let onAdd: (SkillId, Int) -> Void

    private(set) var phase: Phase = .judging
    private(set) var entries: [AdditionalSkillFinder.Entry] = []
    private(set) var determinedCount = 0
    private(set) var targetCount = 0
    private(set) var pendingCount = 0

    /// 未判定分からの再開用(仕様3.5手順5)。sheetを閉じたらVMごと破棄される
    private var checkpoint: AdditionalSkillFinder.Outcome?
    /// 判定開始時に固定する所持護石(sheet表示中に入力は変わらない前提)
    private var ownedCharms: [Charm]?
    private var task: Task<Void, Never>?
    private var cancelDetachedWork: [() -> Void] = []

    /// ステージ時間予算(仕様Q-15)
    private static let budget: Duration = .seconds(8)

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
        case .set: return skill.name + "(シリーズ)"
        case .group: return skill.name + "(グループ)"
        case .armor, .weapon: return skill.name
        }
    }

    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        run(resuming: nil)
    }

    /// 「続きを探す」: 未判定分のみ判定を再開(確定済みは再計算しない)
    func continueSearch() {
        guard phase == .list, pendingCount > 0 else { return }
        phase = .judging
        run(resuming: checkpoint)
    }

    func retry() {
        cancel()
        task = nil
        checkpoint = nil
        entries = []
        phase = .judging
        run(resuming: nil)
    }

    func cancel() {
        task?.cancel()
        cancelDetachedWork.forEach { $0() }
        cancelDetachedWork.removeAll()
    }

    func select(_ entry: AdditionalSkillFinder.Entry) {
        onAdd(entry.skillId, entry.maxAddableLevel)
    }

    private func run(resuming: AdditionalSkillFinder.Outcome?) {
        let finder = dependencies.additionalSkillFinder
        let condition = condition
        let weapon = weapon
        let ownedCharms = self.ownedCharms ?? dependencies.loadOwnedCharmsForSearch()
        self.ownedCharms = ownedCharms
        task = Task {
            do {
                let work = Task.detached(priority: .userInitiated) {
                    try finder.find(
                        condition: condition, weapon: weapon, ownedCharms: ownedCharms,
                        resuming: resuming,
                        onSkillDetermined: { [weak self] determined, total in
                            Task { @MainActor [weak self] in
                                self?.determinedCount = determined
                                self?.targetCount = total
                            }
                        })
                }
                cancelDetachedWork.append { work.cancel() }
                let timer = Task {
                    try? await Task.sleep(for: Self.budget)
                    work.cancel()
                }
                defer { timer.cancel() }
                let outcome = try await work.value
                guard !Task.isCancelled else { return }
                checkpoint = outcome
                entries = outcome.entries
                determinedCount = outcome.determinedCount
                targetCount = outcome.targetCount
                pendingCount = outcome.pending.count
                // 空=対象0または追加可能0件が確定した場合のみ(仕様3.5エッジケース)。
                // 打ち切りで候補0のときはlist(0件+続きを探す)にする
                phase = outcome.entries.isEmpty && outcome.isExhaustive ? .empty : .list
                task = nil
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
                task = nil
            }
        }
    }
}
