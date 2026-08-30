import Foundation
import Observation
import MHSimulatorCore

/// スキル選択sheet(画面設計4.2)。検索+分類フィルタで179スキルを絞り込む
@Observable
final class SkillPickerViewModel {
    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "すべて"
        case weapon = "武器"
        case armor = "防具"
        case set = "シリーズ"
        case group = "グループ"

        var id: String { rawValue }

        /// 表示ラベル(rawValueは識別子として保持し、表示はローカライズする)
        var label: String {
            switch self {
            case .all: String(localized: "すべて")
            case .weapon: String(localized: "武器")
            case .armor: String(localized: "防具")
            case .set: String(localized: "シリーズ")
            case .group: String(localized: "グループ")
            }
        }

        var skillKind: SkillKind? {
            switch self {
            case .all: nil
            case .weapon: .weapon
            case .armor: .armor
            case .set: .set
            case .group: .group
            }
        }
    }

    private let master: MasterDatabase
    var searchText = ""
    var kindFilter: KindFilter = .all

    init(master: MasterDatabase) {
        self.master = master
    }

    /// 絞り込み結果。名前昇順
    var visibleSkills: [Skill] {
        master.skills.values
            .filter { skill in
                (kindFilter.skillKind == nil || skill.kind == kindFilter.skillKind)
                    && skill.name.mhContains(searchText)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
