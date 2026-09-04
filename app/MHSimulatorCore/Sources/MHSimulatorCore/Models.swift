import Foundation

// マスタデータのid はゲーム内部ID(Int32・負値あり)をそのまま使う(仕様4章)

public typealias SkillId = Int32

public enum SkillKind: String, Sendable {
    case armor, weapon, set, group
}

public struct Skill: Sendable, Identifiable {
    public let id: SkillId
    public let name: String
    public let kind: SkillKind
    public let maxLevel: Int
    /// 説明文(ゲーム内文言。マスタ未収録スキルはnil)
    public let summary: String?
    /// レベル→効果文(SkillRank。ゲーム内文言のため改行を含む)
    public let levelEffects: [Int: String]
}

public enum ArmorPieceKind: String, CaseIterable, Sendable {
    case head, chest, arms, waist, legs
}

public struct ArmorPiece: Sendable, Identifiable {
    public let id: Int64
    public let seriesId: Int32
    public let kind: ArmorPieceKind
    public let name: String
    public let defenseMax: Int
    public let resistances: [Int]  // fire, water, thunder, ice, dragon
    public let slots: [Int]        // サイズの配列(降順とは限らない)
    /// 限界突破後のスロット(レア5=全3スロ+1 / レア6=左2スロ+1 / 上限3。対象外はslotsと同値。仕様4.1)
    public let limitBreakSlots: [Int]
    public let skills: [SkillId: Int]

    /// 限界突破を考慮した検索用のコピー(slotsを限界突破後の値に差し替える)。
    /// 結果スナップショットにも差し替え後が残るため、表示は検索時の設定と常に一致する
    func applyingLimitBreak() -> ArmorPiece {
        guard slots != limitBreakSlots else { return self }
        return ArmorPiece(
            id: id, seriesId: seriesId, kind: kind, name: name,
            defenseMax: defenseMax, resistances: resistances,
            slots: limitBreakSlots, limitBreakSlots: limitBreakSlots, skills: skills)
    }
}

public struct ArmorSeriesBonus: Sendable {
    public let skillId: SkillId
    /// 部位数 → 発動レベル(例 [2:1, 4:2])
    public let ranksByPieces: [Int: Int]

    /// 装着部位数に対する発動レベル
    public func level(forPieces count: Int) -> Int {
        ranksByPieces.filter { $0.key <= count }.values.max() ?? 0
    }
}

public struct ArmorSeries: Sendable {
    public let id: Int32
    public let name: String
    public let rarity: Int
    public let setBonus: ArmorSeriesBonus?    // 2/4部位
    public let groupBonus: ArmorSeriesBonus?  // 3部位
}

public enum DecorationTarget: String, Sendable {
    case weapon, armor
}

public struct Decoration: Sendable {
    public let id: Int32
    public let name: String
    public let slotSize: Int
    public let allowedOn: DecorationTarget
    public let skills: [SkillId: Int]
}

/// 検索エンジンが扱う護石(固定護石・所持鑑定護石を統一した形)
public struct Charm: Sendable {
    public enum Source: Equatable, Sendable {
        case none                 // 護石なし
        case fixed(Int32, Int)    // 固定護石(系統ID, ランク)
        case owned(UUID)          // 所持鑑定護石
    }
    public let source: Source
    public let name: String
    public let skills: [SkillId: Int]
    public let weaponSlots: [Int]
    public let armorSlots: [Int]

    public static let none = Charm(source: .none, name: "護石なし", skills: [:], weaponSlots: [], armorSlots: [])

    public init(source: Source, name: String, skills: [SkillId: Int], weaponSlots: [Int], armorSlots: [Int]) {
        self.source = source
        self.name = name
        self.skills = skills
        self.weaponSlots = weaponSlots
        self.armorSlots = armorSlots
    }
}

public struct Weapon: Sendable {
    public let id: Int64
    public let kind: String
    public let name: String
    public let rarity: Int
    public let slots: [Int]
    public let skills: [SkillId: Int]
    /// 基礎攻撃力(武器係数なし。bundled.db Weapon.attackRaw。装備比較F-11で使用。2026-09-04追加)
    public let attackRaw: Int
    /// 会心率(%)。bundled.db Weapon.affinity
    public let affinity: Int

    public init(
        id: Int64, kind: String, name: String, rarity: Int, slots: [Int], skills: [SkillId: Int],
        attackRaw: Int = 0, affinity: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.rarity = rarity
        self.slots = slots
        self.skills = skills
        self.attackRaw = attackRaw
        self.affinity = affinity
    }
}

// MARK: - 検索条件と結果

/// ウィッシュリスト項目(欲しい鑑定護石の要求。画面設計4.6 2026-08-25追加)
public struct WishlistItem: Identifiable, Sendable {
    public let id: UUID
    /// 要求スキル(順序保持・最大3件)
    public var skills: [CharmRules.GroupEntry]
    public var weaponSlots: [Int]
    public var armorSlots: [Int]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        skills: [CharmRules.GroupEntry],
        weaponSlots: [Int] = [],
        armorSlots: [Int] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.skills = skills
        self.weaponSlots = weaponSlots
        self.armorSlots = armorSlots
        self.createdAt = createdAt
    }

    public var requirement: CharmRules.Requirement {
        CharmRules.Requirement(
            skills: Dictionary(skills.map { ($0.skillId, $0.level) }) { max($0, $1) },
            weaponSlots: weaponSlots,
            armorSlots: armorSlots)
    }
}

public struct SearchCondition: Sendable {
    /// スキルID → 目標レベル。Dictionaryのため同一スキルの重複指定は構造的に起きない(仕様3.1)
    public let requiredSkills: [SkillId: Int]
    /// 部位ごとの固定防具(必ず使う。ArmorPiece.id)。固定部位は候補がその1択になる(2026-08-24追加)
    public let pinnedPieceIds: [ArmorPieceKind: Int64]
    /// 除外する防具のid集合(候補から外す)
    public let excludedPieceIds: Set<Int64>
    /// 固定する生産護石の系統ID(Charm.Source.fixedの第1要素)。指定時は護石候補がその1択になる
    public let pinnedFixedCharmId: Int32?
    /// 除外する生産護石の系統ID集合
    public let excludedFixedCharmIds: Set<Int32>
    /// 除外する装飾品のid集合(割り当て候補から外す。簡易所持数管理=F-7拡張 2026-08-29)
    public let excludedDecorationIds: Set<Int32>
    /// 防具の限界突破を考慮する(レア5・6のスロット拡張。既定ON。2026-08-30追加)
    public let considerLimitBreak: Bool

    public init(
        requiredSkills: [SkillId: Int],
        pinnedPieceIds: [ArmorPieceKind: Int64] = [:],
        excludedPieceIds: Set<Int64> = [],
        pinnedFixedCharmId: Int32? = nil,
        excludedFixedCharmIds: Set<Int32> = [],
        excludedDecorationIds: Set<Int32> = [],
        considerLimitBreak: Bool = true
    ) {
        self.requiredSkills = requiredSkills
        self.pinnedPieceIds = pinnedPieceIds
        self.excludedPieceIds = excludedPieceIds
        self.pinnedFixedCharmId = pinnedFixedCharmId
        self.excludedFixedCharmIds = excludedFixedCharmIds
        self.excludedDecorationIds = excludedDecorationIds
        self.considerLimitBreak = considerLimitBreak
    }
}

public struct DecorationAssignment: Sendable {
    public enum SlotOwner: Hashable, Sendable {
        case weapon
        case armor(ArmorPieceKind)
        case charmWeapon
        case charmArmor
    }
    public let owner: SlotOwner
    public let slotSize: Int
    public let decoration: Decoration
    /// この枠が実際に埋めた不足分(スキル→レベル。割り当て時に記録)。
    /// 必要分を満たす別の装飾品と交換しても成立が崩れない(装備詳細の代替可能表示=仕様3.1手順5)
    public let required: [SkillId: Int]

    public init(owner: SlotOwner, slotSize: Int, decoration: Decoration, required: [SkillId: Int] = [:]) {
        self.owner = owner
        self.slotSize = slotSize
        self.decoration = decoration
        self.required = required
    }
}

public struct EquipmentSet: Sendable {
    /// 採用武器(固定選択またはエンジンの自動選択。2026-08-24改訂)
    public let weapon: Weapon?
    public let pieces: [ArmorPieceKind: ArmorPiece]
    public let charm: Charm
    public let decorations: [DecorationAssignment]
    /// 発動スキル(シリーズ/グループスキル込み、maxLevelでクリップ済み)
    public let activeSkills: [SkillId: Int]
    public let totalDefenseMax: Int
    public let totalResistances: [Int]
    /// 装飾品割り当て後の空きスロット(サイズの配列)
    public let emptyWeaponSlots: [Int]
    public let emptyArmorSlots: [Int]
}

public struct SearchResult: Sendable {
    public let sets: [EquipmentSet]
    /// 上限件数(仕様Q-3: 100件)で打ち切られたか
    public let truncated: Bool
}

public enum SearchError: Error, Equatable, Sendable {
    case emptyCondition                   // 条件スキル0個
    case levelExceedsMax(SkillId)         // 目標レベルが上限超
    case unknownSkill(SkillId)
}

// MARK: - Codable準拠(マイセット保存=EquipmentSetのスナップショットJSON化。画面設計4.15 2026-08-29追加)
// 自動合成は型宣言と同一ファイルのextensionでのみ働くため、ここにまとめて置く

extension ArmorPieceKind: Codable {}
extension ArmorPiece: Codable {
    // 後方互換デコード: limitBreakSlots追加(2026-08-30)前に保存されたマイセットはslotsで埋める
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let slots = try c.decode([Int].self, forKey: .slots)
        self.init(
            id: try c.decode(Int64.self, forKey: .id),
            seriesId: try c.decode(Int32.self, forKey: .seriesId),
            kind: try c.decode(ArmorPieceKind.self, forKey: .kind),
            name: try c.decode(String.self, forKey: .name),
            defenseMax: try c.decode(Int.self, forKey: .defenseMax),
            resistances: try c.decode([Int].self, forKey: .resistances),
            slots: slots,
            limitBreakSlots: try c.decodeIfPresent([Int].self, forKey: .limitBreakSlots) ?? slots,
            skills: try c.decode([SkillId: Int].self, forKey: .skills))
    }
}
extension DecorationTarget: Codable {}
extension Decoration: Codable {}
extension Charm.Source: Codable {}
extension Charm: Codable {}
extension Weapon: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, rarity, slots, skills, attackRaw, affinity
    }

    /// attackRaw/affinityは2026-09-04追加。それ以前に保存したマイセットのスナップショットには
    /// キーが無いため0として読む(表示時は武器IDでマスタを再参照する)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(Int64.self, forKey: .id),
            kind: try c.decode(String.self, forKey: .kind),
            name: try c.decode(String.self, forKey: .name),
            rarity: try c.decode(Int.self, forKey: .rarity),
            slots: try c.decode([Int].self, forKey: .slots),
            skills: try c.decode([SkillId: Int].self, forKey: .skills),
            attackRaw: try c.decodeIfPresent(Int.self, forKey: .attackRaw) ?? 0,
            affinity: try c.decodeIfPresent(Int.self, forKey: .affinity) ?? 0)
    }
}
extension DecorationAssignment.SlotOwner: Codable {}
extension DecorationAssignment: Codable {}
extension EquipmentSet: Codable {}
