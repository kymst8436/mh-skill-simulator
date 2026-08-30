import Foundation
import Observation
import MHSimulatorCore

/// 護石入力(画面設計4.7)。抽選規則で候補を絞り、あり得ない護石は構造的に入力不能にする
@Observable
final class CharmEntryViewModel {
    let dependencies: AppDependencies
    private let editingId: UUID?
    private var initialSnapshot = Snapshot(skills: [nil, nil, nil], slot: nil, memo: "")

    var skill1: CharmRules.GroupEntry?
    var skill2: CharmRules.GroupEntry?
    var skill3: CharmRules.GroupEntry?
    var selectedSlot: CharmRules.RaritySlots?
    /// カメラ読み取りで確定したレア度(スロット候補を絞る。手動でスキルを変えると解除=F-10)
    private(set) var scannedRarity: Int?
    var memo = ""
    private(set) var isSaving = false
    var saveErrorMessage: String?

    private var rules: CharmRules { dependencies.master.charmRules }

    struct Snapshot: Equatable {
        var skills: [CharmRules.GroupEntry?]
        var slot: CharmRules.RaritySlots?
        var memo: String
    }

    init(dependencies: AppDependencies, target: CharmEntryTarget) {
        self.dependencies = dependencies
        switch target {
        case .new:
            editingId = nil
        case .edit(let charm):
            editingId = charm.id
            let skills = charm.skills
            skill1 = skills.count > 0 ? skills[0] : nil
            skill2 = skills.count > 1 ? skills[1] : nil
            skill3 = skills.count > 2 ? skills[2] : nil
            if let rarity = charm.rarity {
                selectedSlot = CharmRules.RaritySlots(
                    rarity: rarity,
                    slots: CharmRules.SlotCombo(
                        weaponSlots: charm.weaponSlots, armorSlots: charm.armorSlots))
            }
            memo = charm.memo
        case .preset(let requirement):
            editingId = nil
            applyPreset(requirement)
        }
        initialSnapshot = Snapshot(skills: [skill1, skill2, skill3], slot: selectedSlot, memo: memo)
    }

    var isEditing: Bool { editingId != nil }
    var isDirty: Bool {
        Snapshot(skills: [skill1, skill2, skill3], slot: selectedSlot, memo: memo) != initialSnapshot
    }
    var canSave: Bool { skill1 != nil && selectedSlot != nil && !isSaving }
    var rulesUnavailable: Bool { rules.isEmpty }

    // MARK: - 候補(規則評価)

    private var chosenPrefix: [CharmRules.GroupEntry] {
        var prefix: [CharmRules.GroupEntry] = []
        if let skill1 { prefix.append(skill1) } else { return prefix }
        if let skill2 { prefix.append(skill2) } else { return prefix }
        if let skill3 { prefix.append(skill3) }
        return prefix
    }

    /// スキルN枠(0始まり)の候補。名前昇順→レベル昇順
    func candidates(forPosition position: Int) -> [CharmRules.GroupEntry] {
        let previous = Array([skill1, skill2, skill3].prefix(position)).compactMap { $0 }
        guard previous.count == position else { return [] }  // 前段未確定なら空(UI側で無効化)
        return rules.candidates(forPosition: position, previous: previous)
            .sorted {
                let name0 = skillName($0.skillId)
                let name1 = skillName($1.skillId)
                if name0 != name1 {
                    return name0.localizedStandardCompare(name1) == .orderedAscending
                }
                return $0.level < $1.level
            }
    }

    /// 選択と後段の連鎖無効化(スキル1変更→2・3があり得なければクリア)
    func select(position: Int, entry: CharmRules.GroupEntry?) {
        scannedRarity = nil  // 手動変更で読み取りレア度の絞り込みを解除
        switch position {
        case 0: skill1 = entry
        case 1: skill2 = entry
        default: skill3 = entry
        }
        if position <= 0, let current = skill2,
           !rules.candidates(forPosition: 1, previous: chosenPrefixUpTo(1)).contains(current) {
            skill2 = nil
        }
        if skill2 == nil { skill3 = nil }
        if position <= 1, let current = skill3,
           !rules.candidates(forPosition: 2, previous: chosenPrefixUpTo(2)).contains(current) {
            skill3 = nil
        }
        refreshSlotSelection()
    }

    private func chosenPrefixUpTo(_ position: Int) -> [CharmRules.GroupEntry] {
        Array([skill1, skill2, skill3].prefix(position)).compactMap { $0 }
    }

    /// 現在の絞り込み条件でのスロット候補集合(読み取りレア度があればそのレア度のみ)
    private func availableSlotCandidates() -> Set<CharmRules.RaritySlots> {
        let all = rules.slotCandidates(for: chosenPrefix)
        guard let scannedRarity else { return all }
        let filtered = all.filter { $0.rarity == scannedRarity }
        return filtered.isEmpty ? all : filtered  // 矛盾時は絞り込みを諦めて全候補
    }

    /// スロット・レア度候補。レア度昇順→スロット数降順(仕様3.3 手順4)
    var slotCandidates: [CharmRules.RaritySlots] {
        var list = availableSlotCandidates().sorted {
            if $0.rarity != $1.rarity { return $0.rarity < $1.rarity }
            let count0 = $0.slots.weaponSlots.count + $0.slots.armorSlots.count
            let count1 = $1.slots.weaponSlots.count + $1.slots.armorSlots.count
            return count0 > count1
        }
        // 編集時: 旧規則で登録済みの構成が現候補に無い場合もそのまま有効(仕様3.3エッジケース)
        if let selectedSlot, !list.contains(selectedSlot) {
            list.append(selectedSlot)
        }
        return list
    }

    private func refreshSlotSelection() {
        let candidates = availableSlotCandidates()
        if let selectedSlot, !candidates.contains(selectedSlot) {
            self.selectedSlot = nil
        }
        // 候補が1つなら自動選択(画面設計4.7 構成要素6)
        if selectedSlot == nil, candidates.count == 1 {
            selectedSlot = candidates.first
        }
    }

    // MARK: - プリセット(逆引き候補→登録。画面設計4.7 初期(プリセット))

    private func applyPreset(_ requirement: CharmRules.Requirement) {
        var remaining = requirement.skills
        for position in 0..<3 where !remaining.isEmpty {
            let previous = chosenPrefixUpTo(position)
            guard previous.count == position else { break }
            let candidates = rules.candidates(forPosition: position, previous: previous)
            // 要求スキルを満たす最小レベルの候補を割り当てる
            let match = candidates
                .filter { candidate in
                    guard let required = remaining[candidate.skillId] else { return false }
                    return candidate.level >= required
                }
                .min { $0.level < $1.level }
            guard let match else { continue }
            select(position: position, entry: match)
            remaining.removeValue(forKey: match.skillId)
        }
        // 要求スロットを満たす最小レア度の候補を選ぶ
        if selectedSlot == nil {
            selectedSlot = rules.slotCandidates(for: chosenPrefix)
                .filter {
                    CharmRules.fits(required: requirement.weaponSlots, available: $0.slots.weaponSlots)
                        && CharmRules.fits(required: requirement.armorSlots, available: $0.slots.armorSlots)
                }
                .min { $0.rarity < $1.rarity }
        }
    }

    // MARK: - カメラ読み取り(F-10。画面設計4.13)

    /// スキャン確定スキル(規則順に整列済み)と読み取りレア度を反映する。
    /// レア度が読めていればスロット候補をそのレア度に絞る(候補1つなら自動選択)
    func applyScanned(_ entries: [CharmRules.GroupEntry], rarity: Int?) {
        skill1 = nil
        skill2 = nil
        skill3 = nil
        selectedSlot = nil
        for (position, entry) in entries.prefix(3).enumerated() {
            select(position: position, entry: entry)
        }
        scannedRarity = rarity
        refreshSlotSelection()
    }

    // MARK: - 保存(仕様3.3 手順6)

    func makeCharm() -> OwnedCharm {
        OwnedCharm(
            id: editingId ?? UUID(),
            skills: [skill1, skill2, skill3].compactMap { $0 },
            weaponSlots: selectedSlot?.slots.weaponSlots ?? [],
            armorSlots: selectedSlot?.slots.armorSlots ?? [],
            rarity: selectedSlot?.rarity,
            memo: memo)
    }

    /// 完全一致の登録済み護石があるか(重複登録警告)
    func hasDuplicate() -> Bool {
        (try? dependencies.userStore.hasDuplicate(of: makeCharm(), excluding: editingId)) ?? false
    }

    /// 保存。成功でtrue。失敗時は入力保持のままエラー文言を出す
    func save() -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let charm = makeCharm()
            if isEditing {
                try dependencies.userStore.update(charm)
            } else {
                try dependencies.userStore.insert(charm)
            }
            return true
        } catch {
            saveErrorMessage = String(localized: "保存できませんでした。端末の空き容量をご確認ください")
            return false
        }
    }

    func skillName(_ id: SkillId) -> String {
        dependencies.master.skills[id]?.name ?? "?"
    }

    func entryLabel(_ entry: CharmRules.GroupEntry?) -> String {
        guard let entry else { return String(localized: "(なし)") }
        return MHFormat.skillLine(skillName(entry.skillId), entry.level)
    }

    func slotLabel(_ slot: CharmRules.RaritySlots) -> String {
        MHFormat.emptySlotSummary(weapon: slot.slots.weaponSlots, armor: slot.slots.armorSlots)
    }

    /// スロットセクションの注記(読み取りレア度で絞り込み中はその旨を示す)
    var slotNote: String {
        if let scannedRarity {
            return String(localized: "読み取ったレア度(RARE \(scannedRarity))で候補を絞り込んでいます")
        }
        return String(localized: "スキル構成から自動で候補を絞り込みます")
    }
}
