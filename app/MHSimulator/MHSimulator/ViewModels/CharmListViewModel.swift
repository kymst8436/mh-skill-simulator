import Foundation
import Observation
import MHSimulatorCore

/// 護石一覧(画面設計4.6)
@Observable
final class CharmListViewModel {
    /// 所持護石の並び替え(2026-08-27追加)。nil=既定(登録日時降順)
    enum SortOrder: String, CaseIterable, Identifiable {
        case rarityAscending = "レア度昇順"
        case rarityDescending = "レア度降順"
        case slotAscending = "スロット数昇順"
        case slotDescending = "スロット数降順"
        var id: String { rawValue }
    }

    /// 護石レア度の取り得る範囲(抽選規則=仕様4.2)
    static let filterableRarities = [5, 6, 7, 8]

    let dependencies: AppDependencies
    private(set) var charms: [OwnedCharm] = []
    /// 所持護石の検索語(2026-08-27追加。スキル名の部分一致・ひらがな/カタカナ同一視=mhContains)
    var searchText = ""
    /// レア度フィルター(複数選択=OR条件。2026-08-27追加)
    var filterRarities: Set<Int> = []
    /// 「武器スロあり」フィルター(レア度と同じくOR条件の一員)
    var filterWeaponSlot = false
    /// 並び替え。選択中の項目を再タップで既定に戻す
    var sortOrder: SortOrder?
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

    /// 検索語・フィルター・並び替えを適用した所持護石。
    /// フィルターは選択項目のOR条件、検索語とはAND(2026-08-27追加)
    var filteredCharms: [OwnedCharm] {
        var result = charms
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { displayName($0).mhContains(query) }
        }
        if isFilterActive {
            result = result.filter { charm in
                if let rarity = charm.rarity, filterRarities.contains(rarity) { return true }
                if filterWeaponSlot && !charm.weaponSlots.isEmpty { return true }
                return false
            }
        }
        guard let sortOrder else { return result }  // 既定=登録日時降順(load順)
        // インデックスをタイブレークに使い安定ソートにする(Swiftのsortは安定性未保証)
        let indexed = result.enumerated()
        func slotCount(_ charm: OwnedCharm) -> Int { charm.weaponSlots.count + charm.armorSlots.count }
        switch sortOrder {
        case .rarityAscending:
            return indexed.sorted {
                let r0 = $0.element.rarity ?? Int.max, r1 = $1.element.rarity ?? Int.max  // 未設定は末尾
                return r0 != r1 ? r0 < r1 : $0.offset < $1.offset
            }.map(\.element)
        case .rarityDescending:
            return indexed.sorted {
                let r0 = $0.element.rarity ?? Int.min, r1 = $1.element.rarity ?? Int.min
                return r0 != r1 ? r0 > r1 : $0.offset < $1.offset
            }.map(\.element)
        case .slotAscending:
            return indexed.sorted {
                let s0 = slotCount($0.element), s1 = slotCount($1.element)
                return s0 != s1 ? s0 < s1 : $0.offset < $1.offset
            }.map(\.element)
        case .slotDescending:
            return indexed.sorted {
                let s0 = slotCount($0.element), s1 = slotCount($1.element)
                return s0 != s1 ? s0 > s1 : $0.offset < $1.offset
            }.map(\.element)
        }
    }

    /// フィルターが1つでも選択されているか(アイコン強調表示の条件)
    var isFilterActive: Bool { !filterRarities.isEmpty || filterWeaponSlot }

    /// 検索語またはフィルターで絞り込み中か(件数の「一致m/n個」表示の条件)
    var isNarrowed: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || isFilterActive
    }

    /// 「すべて表示」: フィルター条件を全て解除する(2026-08-27追加)
    func clearFilters() {
        filterRarities.removeAll()
        filterWeaponSlot = false
    }

    func toggleRarityFilter(_ rarity: Int) {
        if filterRarities.contains(rarity) {
            filterRarities.remove(rarity)
        } else {
            filterRarities.insert(rarity)
        }
    }

    /// 並び替え選択(選択中の項目を再タップで既定=登録日時降順に戻す)
    func selectSortOrder(_ order: SortOrder) {
        sortOrder = sortOrder == order ? nil : order
    }

    func slotText(_ charm: OwnedCharm) -> String {
        MHFormat.emptySlotSummary(weapon: charm.weaponSlots, armor: charm.armorSlots)
    }
}
