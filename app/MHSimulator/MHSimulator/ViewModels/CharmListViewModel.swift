import Foundation
import Observation
import MHSimulatorCore

/// 護石一覧(画面設計4.6)
@Observable
final class CharmListViewModel {
    let dependencies: AppDependencies
    private(set) var charms: [OwnedCharm] = []
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?
    private(set) var isDeleting = false
    var deleteErrorMessage: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() {
        isLoading = charms.isEmpty
        loadErrorMessage = nil
        do {
            charms = try dependencies.userStore.loadCharms()
        } catch {
            loadErrorMessage = "護石データを読み込めませんでした"
        }
        isLoading = false
    }

    func delete(_ charm: OwnedCharm) {
        guard !isDeleting else { return }  // 削除の連打防止(仕様3.3)
        isDeleting = true
        do {
            try dependencies.userStore.delete(id: charm.id)
            charms.removeAll { $0.id == charm.id }
        } catch {
            deleteErrorMessage = "削除できませんでした。端末の空き容量をご確認ください"
        }
        isDeleting = false
    }

    func displayName(_ charm: OwnedCharm) -> String {
        dependencies.charmDisplayName(charm)
    }

    func slotText(_ charm: OwnedCharm) -> String {
        MHFormat.emptySlotSummary(weapon: charm.weaponSlots, armor: charm.armorSlots)
    }
}
