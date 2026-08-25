import Foundation
import Observation
import MHSimulatorCore

/// 護石一覧(画面設計4.6)
@Observable
final class CharmListViewModel {
    let dependencies: AppDependencies
    private(set) var charms: [OwnedCharm] = []
    private(set) var wishlist: [WishlistItem] = []
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
            wishlist = try dependencies.userStore.loadWishlist()
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

    // MARK: - ウィッシュリスト(2026-08-25追加)

    func deleteWishlistItem(_ item: WishlistItem) {
        do {
            try dependencies.userStore.deleteWishlistItem(id: item.id)
            wishlist.removeAll { $0.id == item.id }
        } catch {
            deleteErrorMessage = "削除できませんでした。端末の空き容量をご確認ください"
        }
    }

    /// 要求の表示文字列(例「攻撃Lv3 + 防具スロ①」)
    func requirementText(_ item: WishlistItem) -> String {
        MHFormat.requirementText(item.requirement, master: dependencies.master)
    }

    /// 要求を満たす護石の最小レア度(表示用)
    func minimumRarity(_ item: WishlistItem) -> Int? {
        dependencies.master.charmRules.minimumRarity(satisfying: item.requirement)
    }

    func displayName(_ charm: OwnedCharm) -> String {
        dependencies.charmDisplayName(charm)
    }

    func slotText(_ charm: OwnedCharm) -> String {
        MHFormat.emptySlotSummary(weapon: charm.weaponSlots, armor: charm.armorSlots)
    }
}
