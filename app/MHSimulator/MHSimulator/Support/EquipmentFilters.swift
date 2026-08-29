import Foundation
import MHSimulatorCore

/// 装備の固定・除外設定(検索設定画面。画面設計4.10。2026-08-24追加)。
/// AppState.searchFilters にJSONで永続化する
nonisolated struct EquipmentFilters: Codable, Equatable {
    /// 部位(rawValue) → 固定する防具のArmorPiece.id
    var pinnedPieces: [String: Int64] = [:]
    /// 除外する防具のid
    var excludedPieces: [Int64] = []
    /// 固定する生産護石の系統ID
    var pinnedCharmId: Int32?
    /// 除外する生産護石の系統ID
    var excludedCharmIds: [Int32] = []
    /// 除外する装飾品のid(簡易所持数管理=F-7拡張。2026-08-29追加)
    var excludedDecorations: [Int32] = []

    init() {}

    /// 後方互換デコード: 追加キーが無い旧JSONでも既存設定を失わない
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinnedPieces = try container.decodeIfPresent([String: Int64].self, forKey: .pinnedPieces) ?? [:]
        excludedPieces = try container.decodeIfPresent([Int64].self, forKey: .excludedPieces) ?? []
        pinnedCharmId = try container.decodeIfPresent(Int32.self, forKey: .pinnedCharmId)
        excludedCharmIds = try container.decodeIfPresent([Int32].self, forKey: .excludedCharmIds) ?? []
        excludedDecorations = try container.decodeIfPresent([Int32].self, forKey: .excludedDecorations) ?? []
    }

    var isEmpty: Bool {
        pinnedPieces.isEmpty && excludedPieces.isEmpty
            && pinnedCharmId == nil && excludedCharmIds.isEmpty
            && excludedDecorations.isEmpty
    }

    func pinnedPieceId(for kind: ArmorPieceKind) -> Int64? {
        pinnedPieces[kind.rawValue]
    }

    /// 固定を設定(同じ防具が除外に入っていたら外す。固定と除外の矛盾防止)
    mutating func setPinnedPiece(_ id: Int64?, for kind: ArmorPieceKind) {
        if let id {
            pinnedPieces[kind.rawValue] = id
            excludedPieces.removeAll { $0 == id }
        } else {
            pinnedPieces.removeValue(forKey: kind.rawValue)
        }
    }

    /// 除外に追加(固定中の防具なら固定を解除)
    mutating func addExcludedPiece(_ id: Int64) {
        guard !excludedPieces.contains(id) else { return }
        excludedPieces.append(id)
        for (key, pinned) in pinnedPieces where pinned == id {
            pinnedPieces.removeValue(forKey: key)
        }
    }

    mutating func setPinnedCharm(_ id: Int32?) {
        pinnedCharmId = id
        if let id { excludedCharmIds.removeAll { $0 == id } }
    }

    mutating func addExcludedCharm(_ id: Int32) {
        guard !excludedCharmIds.contains(id) else { return }
        excludedCharmIds.append(id)
        if pinnedCharmId == id { pinnedCharmId = nil }
    }

    mutating func addExcludedDecoration(_ id: Int32) {
        guard !excludedDecorations.contains(id) else { return }
        excludedDecorations.append(id)
    }

    // MARK: - SearchCondition用の変換

    var pinnedPieceIdsByKind: [ArmorPieceKind: Int64] {
        Dictionary(uniqueKeysWithValues: pinnedPieces.compactMap { key, id in
            ArmorPieceKind(rawValue: key).map { ($0, id) }
        })
    }

    // MARK: - JSON

    func encoded() -> String? {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func decode(_ json: String) -> EquipmentFilters? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(EquipmentFilters.self, from: $0) }
    }
}
