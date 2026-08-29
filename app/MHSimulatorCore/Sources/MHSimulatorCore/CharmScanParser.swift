import Foundation

/// 護石カメラ読み取り(F-10)のOCR結果解釈。仕様3.6の解釈規則を実装する。
/// カメラ・Visionには依存しない(入力は認識済みテキスト+正規化座標)。
public struct CharmScanParser: Sendable {
    /// OCRの1認識結果。座標はガイド枠内の正規化値で、yは上→下に増える(読み取り順)
    public struct ObservedText: Sendable {
        public let text: String
        public let x: Double
        public let y: Double

        public init(text: String, x: Double, y: Double) {
            self.text = text
            self.x = x
            self.y = y
        }
    }

    /// 解釈成立した護石(スキルは規則順に整列済み)。
    /// rarityはゲーム画面のRARE表記から(読めない・規則と矛盾する場合はnil)
    public struct Reading: Hashable, Sendable {
        public let skills: [CharmRules.GroupEntry]
        public let rarity: Int?
    }

    private let rules: CharmRules
    /// 正規化済みスキル名 → SkillId(同名衝突はマスタ上ないが、あれば後勝ちで許容)
    private let normalizedNames: [String: SkillId]

    public init(skillNames: [SkillId: String], rules: CharmRules) {
        self.rules = rules
        var names: [String: SkillId] = [:]
        for (id, name) in skillNames {
            names[Self.normalize(name)] = id
        }
        self.normalizedNames = names
    }

    /// 1フレーム分の認識結果を解釈する。護石として成立しなければnil(読み取り継続)
    public func parse(_ observations: [ObservedText]) -> Reading? {
        var items: [ObservedText] = observations.compactMap {
            let normalized = Self.normalize($0.text)
            return normalized.isEmpty ? nil : ObservedText(text: normalized, x: $0.x, y: $0.y)
        }
        items.sort { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }

        // アンカー: 護石パネルであること(部分一致。見出しはアイコン巻き込み誤読があるため)
        guard items.contains(where: { $0.text.contains("の護石") }),
              items.contains(where: { $0.text.contains("装備スキル") }) else { return nil }

        // スキル名・Lv・レア度トークンをそれぞれ読み取り順で収集
        var names: [SkillId] = []
        var levels: [Int] = []
        var rarity: Int?
        for item in items {
            if let level = Self.levelToken(item.text) {
                levels.append(level)
            } else if let value = Self.rarityToken(item.text) {
                rarity = value
            } else if let id = matchSkillName(item.text) {
                names.append(id)
            }
        }
        guard (1...3).contains(names.count), names.count == levels.count,
              Set(names).count == names.count else { return nil }

        let entries = zip(names, levels).map { CharmRules.GroupEntry(skillId: $0, level: $1) }
        guard let ordered = ruleValidOrder(entries) else { return nil }
        // レア度はスキル構成のスロット候補と整合する場合のみ採用(誤読はnilに落とす)
        if let value = rarity, !rules.slotCandidates(for: ordered).contains(where: { $0.rarity == value }) {
            rarity = nil
        }
        return Reading(skills: ordered, rarity: rarity)
    }

    // MARK: - 正規化・トークン判定

    /// NFKC正規化+空白除去+小文字化(Lv/LV揺れの吸収)
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    /// 正規化済み文字列が単独のレベル表記(lv1〜lv9)なら値を返す。
    /// 護石レベル行「lv1/1」は完全形でないため自然に除外される
    static func levelToken(_ normalized: String) -> Int? {
        guard normalized.count == 3, normalized.hasPrefix("lv"),
              let digit = normalized.last?.wholeNumberValue, digit >= 1 else { return nil }
        return digit
    }

    /// 正規化済み文字列が単独のレア度表記(rare1〜rare9)なら値を返す
    static func rarityToken(_ normalized: String) -> Int? {
        guard normalized.count == 5, normalized.hasPrefix("rare"),
              let digit = normalized.last?.wholeNumberValue, digit >= 1 else { return nil }
        return digit
    }

    /// スキル名照合: 完全一致→曖昧一致(編集距離1以内かつ唯一最小)。仕様3.6
    private func matchSkillName(_ normalized: String) -> SkillId? {
        if let id = normalizedNames[normalized] { return id }
        guard normalized.count >= 2 else { return nil }
        var best: (id: SkillId, distance: Int)?
        var ambiguous = false
        for (name, id) in normalizedNames {
            // 距離1以内は長さ差1以内でしか起きない(枝刈り)
            guard abs(name.count - normalized.count) <= 1 else { continue }
            guard let distance = Self.editDistance(normalized, name, limit: 1) else { continue }
            if let current = best {
                if distance < current.distance {
                    best = (id, distance)
                    ambiguous = false
                } else if distance == current.distance {
                    ambiguous = true
                }
            } else {
                best = (id, distance)
            }
        }
        guard let best, !ambiguous else { return nil }
        return best.id
    }

    /// 編集距離(上限付き)。limitを超えるならnil
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int? {
        let s = Array(a), t = Array(b)
        guard abs(s.count - t.count) <= limit else { return nil }
        var previous = Array(0...t.count)
        for i in 1...max(s.count, 1) where !s.isEmpty {
            var current = [i] + [Int](repeating: 0, count: t.count)
            var rowMin = i
            for j in 1...max(t.count, 1) where !t.isEmpty {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return nil }
            previous = current
        }
        let distance = previous[t.count]
        return distance <= limit ? distance : nil
    }

    // MARK: - 規則検証

    /// 読み取った(スキル,Lv)の並べ替えのうち、抽選規則に順に適合する並びを返す
    private func ruleValidOrder(_ entries: [CharmRules.GroupEntry]) -> [CharmRules.GroupEntry]? {
        permutations(entries).first { candidate in
            candidate.indices.allSatisfy { position in
                rules.candidates(forPosition: position, previous: Array(candidate.prefix(position)))
                    .contains(candidate[position])
            }
        }
    }

    private func permutations(_ entries: [CharmRules.GroupEntry]) -> [[CharmRules.GroupEntry]] {
        guard entries.count > 1 else { return [entries] }
        return entries.indices.flatMap { index -> [[CharmRules.GroupEntry]] in
            var rest = entries
            let head = rest.remove(at: index)
            return permutations(rest).map { [head] + $0 }
        }
    }
}
