import Foundation
import Observation
import MHSimulatorCore

/// マイセット一覧(画面設計4.15 2026-08-29追加)
@Observable
final class MySetListViewModel {
    let dependencies: AppDependencies
    private(set) var savedSets: [SavedEquipmentSet] = []
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?
    private(set) var isDeleting = false
    var deleteErrorMessage: String?

    /// 一覧行の日付表示(登録日)。表示言語のロケール順序で年月日を並べる
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("yMd")
        return formatter
    }()

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() {
        isLoading = savedSets.isEmpty
        loadErrorMessage = nil
        do {
            savedSets = try dependencies.userStore.loadSavedSets()
        } catch {
            loadErrorMessage = String(localized: "マイセットを読み込めませんでした")
        }
        isLoading = false
    }

    func delete(_ item: SavedEquipmentSet) {
        guard !isDeleting else { return }  // 削除の連打防止(護石一覧と同じ)
        isDeleting = true
        do {
            try dependencies.userStore.deleteSavedSet(id: item.id)
            savedSets.removeAll { $0.id == item.id }
        } catch {
            deleteErrorMessage = String(localized: "削除できませんでした。端末の空き容量をご確認ください")
        }
        isDeleting = false
    }

    /// 保存時の条件スキルの1行表示(レベル降順→名前順)。条件がない保存データは発動スキル上位で代替
    func skillSummary(_ item: SavedEquipmentSet) -> String {
        let source = item.conditionSkills.isEmpty ? item.set.activeSkills : item.conditionSkills
        let lines = source
            .compactMap { id, level -> (name: String, level: Int)? in
                guard let skill = dependencies.master.skills[id] else { return nil }
                return (skill.name, level)
            }
            .sorted {
                if $0.level != $1.level { return $0.level > $1.level }
                return $0.name < $1.name
            }
            .map { MHFormat.skillLine($0.name, $0.level) }
        return lines.joined(separator: String(localized: "・"))
    }

    func dateText(_ item: SavedEquipmentSet) -> String {
        Self.dateFormatter.string(from: item.createdAt)
    }
}
