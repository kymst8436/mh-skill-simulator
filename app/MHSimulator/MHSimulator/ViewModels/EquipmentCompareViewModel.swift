import Foundation
import Observation
import MHSimulatorCore

/// 装備比較(F-11。仕様3.7・画面設計4.17)。①マイセット選択と②比較画面で共有する
@Observable
final class EquipmentCompareViewModel {
    typealias Calc = ExpectedAttackCalculator

    enum Side: String, CaseIterable, Codable {
        case base, compare
    }

    /// 武器の攻撃力・会心率をマスタから引けない列の手入力値(カスタム武器・武器なし・マスタ未収録)
    struct ManualWeapon: Codable, Equatable {
        var attack = 200
        var affinity = 0
    }

    /// 排他条件の確認待ち(画面設計ダイアログ8)
    struct PendingExclusive: Identifiable {
        let id = UUID()
        let condition: Calc.Condition
        let conflicts: [Calc.Condition]
    }

    /// 状態行の表示用(左右の和集合・1列)
    struct ConditionRow: Identifiable {
        let condition: Calc.Condition
        let title: String
        let baseLevel: Int?
        let compareLevel: Int?
        var id: Calc.Condition { condition }
    }

    /// 対象装備列の1行(アイコン+名称)
    struct GearLine: Identifiable {
        enum Icon { case weapon(String?), piece(ArmorPieceKind), charm }
        let id: String
        let icon: Icon
        let name: String
    }

    let dependencies: AppDependencies
    private(set) var savedSets: [SavedEquipmentSet] = []
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?

    private(set) var base: SavedEquipmentSet?
    private(set) var compare: SavedEquipmentSet?
    /// UserDefaultsから復元した選択ID(load()で実体に差し替える)
    private var pendingBaseId: UUID?
    private var pendingCompareId: UUID?
    private(set) var conditions: Set<Calc.Condition> = []
    var items = Calc.ItemSelection() { didSet { persist() } }
    private(set) var extraAttack = 0
    private(set) var extraAffinity = 0
    private(set) var manualWeapons: [Side: ManualWeapon] = [:]
    var pendingExclusive: PendingExclusive?

    private let defaults = UserDefaults.standard
    /// restore()中はitemsのdidSet経由のpersist()を抑止する(未読込のbase/compare=nilで上書きしないため)
    private var isRestoring = false
    private enum Keys {
        static let baseId = "tools.equipmentCompare.baseId"
        static let compareId = "tools.equipmentCompare.compareId"
        static let conditions = "tools.equipmentCompare.conditions"
        static let items = "tools.equipmentCompare.items"
        static let extraAttack = "tools.equipmentCompare.extraAttack"
        static let extraAffinity = "tools.equipmentCompare.extraAffinity"
        static let manualWeapons = "tools.equipmentCompare.manualWeapons"
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        restore()
    }

    // MARK: - 読み込み・選択

    func load() {
        isLoading = savedSets.isEmpty
        loadErrorMessage = nil
        do {
            savedSets = try dependencies.userStore.loadSavedSets()
            // 復元したIDを実体に差し替える。削除済みなら未選択に戻す(仕様3.7エッジケース)
            let baseId = pendingBaseId ?? base?.id
            let compareId = pendingCompareId ?? compare?.id
            base = savedSets.first { $0.id == baseId }
            compare = savedSets.first { $0.id == compareId }
            pendingBaseId = nil
            pendingCompareId = nil
        } catch {
            loadErrorMessage = String(localized: "マイセットを読み込めませんでした")
        }
        isLoading = false
    }

    func select(_ set: SavedEquipmentSet, for side: Side) {
        switch side {
        case .base:
            base = set
            if compare?.id == set.id { compare = nil }
        case .compare:
            compare = set
        }
        // 選択が変わったら、どちらの装備にも無い条件のトグルを落とす
        let valid = Set(rows.map(\.condition))
        conditions = conditions.intersection(valid)
        persist()
    }

    func set(for side: Side) -> SavedEquipmentSet? {
        side == .base ? base : compare
    }

    /// 比較側の選択sheetで選べないセット(もう一方の列で選択中)
    func isSelectable(_ set: SavedEquipmentSet, for side: Side) -> Bool {
        let other = side == .base ? compare : base
        return other?.id != set.id
    }

    // MARK: - 状態トグル(排他確認付き)

    func isOn(_ condition: Calc.Condition) -> Bool {
        conditions.contains(condition)
    }

    func toggle(_ condition: Calc.Condition) {
        if conditions.contains(condition) {
            conditions.remove(condition)
            persist()
            return
        }
        let conflicts = Calc.conflicts(turningOn: condition, active: conditions)
        if conflicts.isEmpty {
            conditions.insert(condition)
            persist()
        } else {
            pendingExclusive = PendingExclusive(condition: condition, conflicts: conflicts)
        }
    }

    func confirmExclusive() {
        guard let pending = pendingExclusive else { return }
        conditions.subtract(pending.conflicts)
        conditions.insert(pending.condition)
        pendingExclusive = nil
        persist()
    }

    func cancelExclusive() {
        pendingExclusive = nil
    }

    /// 排他確認の文言「両立しないため<スキル名>がOFFになります」
    func exclusiveMessage(_ pending: PendingExclusive) -> String {
        let names = pending.conflicts.map { rowTitle(for: $0) }
            .joined(separator: String(localized: "・"))
        return String(localized: "両立しないため\(names)がOFFになります")
    }

    // MARK: - 手入力

    func commitExtraAttack(_ text: String) {
        if let v = Int(text.trimmingCharacters(in: .whitespaces)) { extraAttack = max(0, min(999, v)) }
        persist()
    }

    func commitExtraAffinity(_ text: String) {
        if let v = Int(text.trimmingCharacters(in: .whitespaces)) { extraAffinity = max(-100, min(100, v)) }
        persist()
    }

    func commitManualAttack(_ text: String, for side: Side) {
        if let v = Int(text.trimmingCharacters(in: .whitespaces)) {
            manualWeapons[side, default: ManualWeapon()].attack = max(1, min(999, v))
        }
        persist()
    }

    func commitManualAffinity(_ text: String, for side: Side) {
        if let v = Int(text.trimmingCharacters(in: .whitespaces)) {
            manualWeapons[side, default: ManualWeapon()].affinity = max(-100, min(100, v))
        }
        persist()
    }

    func manualWeapon(for side: Side) -> ManualWeapon {
        manualWeapons[side] ?? ManualWeapon()
    }

    // MARK: - 武器の攻撃力・会心率

    struct WeaponStats {
        let attack: Int
        let affinity: Int
        /// マスタから引けず手入力に頼っている
        let isManual: Bool
    }

    func weaponStats(for side: Side) -> WeaponStats? {
        guard let set = set(for: side)?.set else { return nil }
        if let weapon = set.weapon, weapon.id != CustomWeaponConfig.weaponId,
           let master = dependencies.master.weapons.first(where: { $0.id == weapon.id }) {
            return WeaponStats(attack: master.attackRaw, affinity: master.affinity, isManual: false)
        }
        let manual = manualWeapon(for: side)
        return WeaponStats(attack: manual.attack, affinity: manual.affinity, isManual: true)
    }

    // MARK: - 計算結果

    func output(for side: Side) -> Calc.Output? {
        guard let set = set(for: side)?.set, let stats = weaponStats(for: side) else { return nil }
        return Calc.evaluate(Calc.Input(
            baseAttack: stats.attack, weaponAffinity: stats.affinity,
            skills: set.activeSkills, weaponKind: set.weapon?.kind,
            conditions: conditions, items: items,
            extraAttack: extraAttack, extraAffinity: extraAffinity))
    }

    /// 比較−ベースの差分(%)。片方が無ければnil
    var diffPercent: Double? {
        guard let b = output(for: .base), let c = output(for: .compare) else { return nil }
        return Calc.gainPercent(from: b.expected, to: c.expected)
    }

    // MARK: - 状態行・未計上

    var rows: [ConditionRow] {
        let sets = [base, compare].compactMap { $0?.set.activeSkills }
        return Calc.rows(for: sets).map { row in
            ConditionRow(
                condition: row.condition,
                title: rowTitle(for: row.condition, skillIds: row.skillIds),
                baseLevel: level(of: row.skillIds, in: base),
                compareLevel: level(of: row.skillIds, in: compare))
        }
    }

    private func level(of skillIds: [SkillId], in set: SavedEquipmentSet?) -> Int? {
        guard let skills = set?.set.activeSkills else { return nil }
        let levels = skillIds.compactMap { skills[$0] }.filter { $0 > 0 }
        return levels.max()
    }

    private func rowTitle(for condition: Calc.Condition) -> String {
        let ids = Calc.rows(for: [base, compare].compactMap { $0?.set.activeSkills })
            .first { $0.condition == condition }?.skillIds ?? []
        return rowTitle(for: condition, skillIds: ids)
    }

    /// 行ラベル。スキル名(複数なら「・」区切り)+条件の補足(スキル名だけでは状況が分からないもの)
    private func rowTitle(for condition: Calc.Condition, skillIds: [SkillId]) -> String {
        let names = skillIds.compactMap { dependencies.master.skills[$0]?.name }
        let joined = names.joined(separator: String(localized: "・"))
        if let suffix = Self.conditionSuffix(condition) {
            // 日本語は括弧を直付け、欧文は半角スペースを挟む(xcstringsで言語ごとに指定)
            return String(localized: "\(joined)(\(suffix))", comment: "スキル名(条件)")
        }
        return joined
    }

    /// 条件の補足表示(仕様3.7 発動条件)。スキル名で状況が明らかなものはnil
    static func conditionSuffix(_ condition: Calc.Condition) -> String? {
        switch condition {
        case .weakSpot: String(localized: "有効部位", comment: "状態")
        case .wound: String(localized: "傷口", comment: "状態")
        case .enraged: String(localized: "怒り中", comment: "状態")
        case .latentPower, .ambush, .leviathanFury, .lordsFavor, .revolt, .warCry: String(localized: "発動中", comment: "状態")
        case .maxMight: String(localized: "スタミナ満タン", comment: "状態")
        case .adrenalineRush: String(localized: "回避成功後", comment: "状態")
        case .peakPerformance: String(localized: "体力満タン", comment: "状態")
        case .resentment: String(localized: "体力減少", comment: "状態")
        case .heroics: String(localized: "体力わずか", comment: "状態")
        case .offensiveGuard: String(localized: "ジャストガード後", comment: "状態")
        case .counterstrike: String(localized: "吹き飛ばされた後", comment: "状態")
        case .drawAttack: String(localized: "抜刀攻撃", comment: "状態")
        case .frenzyOvercome: String(localized: "狂竜症克服中", comment: "状態")
        case .frenzyInfected: String(localized: "狂竜症感染中", comment: "状態")
        case .foray: String(localized: "毒・麻痺中の相手", comment: "状態")
        case .wet: String(localized: "水濡れ", comment: "状態")
        case .bubble: String(localized: "泡", comment: "状態")
        case .burst: String(localized: "5回継続後", comment: "状態")
        case .counterAttack: String(localized: "相殺後", comment: "状態")
        case .ateMeat: String(localized: "肉を食べた後", comment: "状態")
        case .resonanceNear: String(localized: "ニアー", comment: "状態")
        case .resonanceFar: String(localized: "ファー", comment: "状態")
        case .tetradShot: String(localized: "4発目以降", comment: "状態")
        case .lordsSoul: String(localized: "発動前", comment: "状態")
        case .lordsFury: String(localized: "状態異常中", comment: "状態")
        case .sliding: String(localized: "スライディング後", comment: "状態")
        case .fortify1: String(localized: "1回", comment: "状態")
        case .fortify2: String(localized: "2回", comment: "状態")
        case .festival: String(localized: "祭事期間中", comment: "状態")
        }
    }

    /// 「ベース Lv3 ・ 比較 —」の補助行。比較未選択ならベースだけ
    func levelLine(_ row: ConditionRow) -> String {
        let baseText = String(localized: "ベース") + " " + Self.levelText(row.baseLevel)
        guard compare != nil else { return baseText }
        return baseText + String(localized: "・") + String(localized: "比較") + " " + Self.levelText(row.compareLevel)
    }

    private static func levelText(_ level: Int?) -> String {
        guard let level else { return "—" }
        return "Lv\(level)"
    }

    /// 未計上スキル(仕様3.7-8)の注記。なければnil
    var uncountedNote: String? {
        var parts: [String] = []
        for side in Side.allCases {
            guard let skills = set(for: side)?.set.activeSkills else { continue }
            let names = Calc.uncountedSkills(in: skills).compactMap { dependencies.master.skills[$0]?.name }
            guard !names.isEmpty else { continue }
            let label = side == .base ? String(localized: "ベース") : String(localized: "比較")
            parts.append(names.joined(separator: String(localized: "・")) + "(\(label))")
        }
        guard !parts.isEmpty else { return nil }
        return String(localized: "未計上: \(parts.joined(separator: String(localized: "・")))。その他の攻撃力加算で入力できます")
    }

    // MARK: - 対象装備の表示

    func gearLines(for side: Side) -> [GearLine] {
        guard let set = set(for: side)?.set else { return [] }
        var lines: [GearLine] = []
        if let weapon = set.weapon {
            lines.append(GearLine(id: "weapon", icon: .weapon(MHFormat.weaponIconName(weapon.kind)), name: weapon.name))
        } else {
            lines.append(GearLine(id: "weapon", icon: .weapon(nil), name: "—"))
        }
        for kind in ArmorPieceKind.allCases {
            lines.append(GearLine(id: kind.rawValue, icon: .piece(kind), name: set.pieces[kind]?.name ?? "—"))
        }
        let charmName = set.charm.source == .none ? String(localized: "護石なし") : set.charm.name
        lines.append(GearLine(id: "charm", icon: .charm, name: charmName))
        return lines
    }

    // MARK: - 永続化(UserDefaults)

    private func persist() {
        guard !isRestoring else { return }
        defaults.set(base?.id.uuidString, forKey: Keys.baseId)
        defaults.set(compare?.id.uuidString, forKey: Keys.compareId)
        defaults.set(conditions.map(\.rawValue).sorted(), forKey: Keys.conditions)
        defaults.set(try? JSONEncoder().encode(items), forKey: Keys.items)
        defaults.set(extraAttack, forKey: Keys.extraAttack)
        defaults.set(extraAffinity, forKey: Keys.extraAffinity)
        defaults.set(try? JSONEncoder().encode(manualWeapons), forKey: Keys.manualWeapons)
    }

    private func restore() {
        isRestoring = true
        defer { isRestoring = false }
        // 選択中マイセットはIDだけ復元し、load()で実体に差し替える(itemsの代入より先に読む)
        pendingBaseId = defaults.string(forKey: Keys.baseId).flatMap(UUID.init(uuidString:))
        pendingCompareId = defaults.string(forKey: Keys.compareId).flatMap(UUID.init(uuidString:))
        let rawConditions = defaults.stringArray(forKey: Keys.conditions) ?? []
        conditions = Set(rawConditions.compactMap(Calc.Condition.init(rawValue:)))
        if let data = defaults.data(forKey: Keys.items),
           let decoded = try? JSONDecoder().decode(Calc.ItemSelection.self, from: data) {
            items = decoded
        }
        extraAttack = defaults.integer(forKey: Keys.extraAttack)
        extraAffinity = defaults.integer(forKey: Keys.extraAffinity)
        if let data = defaults.data(forKey: Keys.manualWeapons),
           let decoded = try? JSONDecoder().decode([Side: ManualWeapon].self, from: data) {
            manualWeapons = decoded
        }
    }

    /// ベース未選択(①で選び直す状態)か
    var hasBase: Bool { base != nil }
}
