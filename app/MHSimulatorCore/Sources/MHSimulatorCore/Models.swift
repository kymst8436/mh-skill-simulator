import Foundation

// マスタデータのid はゲーム内部ID(Int32・負値あり)をそのまま使う(仕様4章)

public typealias SkillId = Int32

public enum SkillKind: String, Sendable {
    case armor, weapon, set, group
}

public struct Skill: Sendable {
    public let id: SkillId
    public let name: String
    public let kind: SkillKind
    public let maxLevel: Int
}

public enum ArmorPieceKind: String, CaseIterable, Sendable {
    case head, chest, arms, waist, legs
}

public struct ArmorPiece: Sendable {
    public let id: Int64
    public let seriesId: Int32
    public let kind: ArmorPieceKind
    public let name: String
    public let defenseMax: Int
    public let resistances: [Int]  // fire, water, thunder, ice, dragon
    public let slots: [Int]        // サイズの配列(降順とは限らない)
    public let skills: [SkillId: Int]
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

    public init(id: Int64, kind: String, name: String, rarity: Int, slots: [Int], skills: [SkillId: Int]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.rarity = rarity
        self.slots = slots
        self.skills = skills
    }
}

// MARK: - 検索条件と結果

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

    public init(
        requiredSkills: [SkillId: Int],
        pinnedPieceIds: [ArmorPieceKind: Int64] = [:],
        excludedPieceIds: Set<Int64> = [],
        pinnedFixedCharmId: Int32? = nil,
        excludedFixedCharmIds: Set<Int32> = []
    ) {
        self.requiredSkills = requiredSkills
        self.pinnedPieceIds = pinnedPieceIds
        self.excludedPieceIds = excludedPieceIds
        self.pinnedFixedCharmId = pinnedFixedCharmId
        self.excludedFixedCharmIds = excludedFixedCharmIds
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
