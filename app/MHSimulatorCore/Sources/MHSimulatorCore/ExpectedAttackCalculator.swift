import Foundation

/// 装備比較(F-11。仕様3.7)の期待値計算。プラットフォーム非依存・テスト対象。
///
/// 物理の「会心込み攻撃力」を、装備の発動スキル・戦闘中の状態(条件トグル)・アイテムから求める。
/// 定数表はゲーム内効果文(マスタSkillRank)と攻略サイトの実測値(仕様3.7に出典)を転記したもの。
/// TUで値が変わり得るため、ExpectedAttackCalculatorTestsでマスタの効果文と突合する。
public enum ExpectedAttackCalculator {

    // MARK: - 条件(状態トグル)

    /// 戦闘中の状態。行=条件で、同じ条件を共有するスキル(抜刀術【技】【力】)は1行にまとまる
    public enum Condition: String, CaseIterable, Hashable, Sendable, Codable {
        case weakSpot          // 有効部位(弱点特効)
        case wound             // 傷口(弱点特効。有効部位と両立)
        case enraged           // 怒り中(挑戦者)
        case latentPower       // 力の解放 発動中
        case maxMight          // スタミナ満タン(渾身)
        case adrenalineRush    // 回避成功後(巧撃)
        case peakPerformance   // 体力満タン(フルチャージ)
        case resentment        // 体力減少・赤ゲージ(逆恨み)
        case heroics           // 体力残りわずか(火事場力)
        case offensiveGuard    // ジャストガード後(攻めの守勢)
        case ambush            // 急襲 発動中
        case counterstrike     // 吹き飛ばされた後(逆襲)
        case drawAttack        // 抜刀攻撃(抜刀術【技】【力】)
        case frenzyOvercome    // 狂竜症克服中(無我の境地・黒蝕竜の力。ゲーム仕様で会心+15%)
        case frenzyInfected    // 狂竜症感染中(黒蝕竜の力)
        case foray             // 毒・麻痺中の相手(攻勢)
        case wet               // 水濡れ(濡れ刃紋)
        case bubble            // 泡(濡れ刃紋)
        case burst             // 連撃 5回継続後(連撃・兇爪竜の力)
        case counterAttack     // 相殺・鍔迫り合い後(闢獣の力)
        case ateMeat           // 肉を食べた後(暗器蛸の力)
        case leviathanFury     // 蒼雷一閃 発動中(海竜の渦雷)
        case resonanceNear     // レゾナンス: ニアー(オメガレゾナンス)
        case resonanceFar      // レゾナンス: ファー(オメガレゾナンス)
        case tetradShot        // 4発目以降(フォースショット)
        case lordsFavor        // 激励 発動中(ヌシの誇り)
        case lordsSoul         // 根性【果敢】発動前(ヌシの魂)
        case lordsFury         // 自分が状態異常中(ヌシの憤激)
        case sliding           // スライディング後(革細工の滑性)
        case fortify1          // 不屈: 力尽きた1回(毛皮の昂揚)
        case fortify2          // 不屈: 力尽きた2回(毛皮の昂揚)
        case revolt            // 束縛反攻 発動中(凍峰竜の反逆)
        case warCry            // ウォークライ 発動中(雪獅子の闘志)
        case festival          // 祭事期間中(祈り系)
    }

    /// 両立しない条件のグループ(仕様3.7 排他グループ①〜⑤)。同じ配列内の異なる集合同士が排他
    public static let exclusiveGroups: [[Set<Condition>]] = [
        [[.peakPerformance], [.resentment, .heroics]],
        [[.wet], [.bubble]],
        [[.frenzyInfected], [.frenzyOvercome]],
        [[.resonanceNear], [.resonanceFar]],
        [[.fortify1], [.fortify2]],
    ]

    /// `condition`をONにしたときにOFFにしなければならない、現在ONの条件(表示順)
    public static func conflicts(turningOn condition: Condition, active: Set<Condition>) -> [Condition] {
        var result: [Condition] = []
        for group in exclusiveGroups {
            guard let own = group.first(where: { $0.contains(condition) }) else { continue }
            for other in group where other != own {
                result.append(contentsOf: Condition.allCases.filter { other.contains($0) && active.contains($0) })
            }
        }
        return result
    }

    // MARK: - 効果

    public struct Effect: Sendable, Equatable {
        public var attackAdd: Int = 0
        public var attackMul: Double = 1
        public var affinityAdd: Int = 0
        /// 会心倍率(超会心)。nil=変更なし
        public var critMultiplier: Double? = nil

        public init(attackAdd: Int = 0, attackMul: Double = 1, affinityAdd: Int = 0, critMultiplier: Double? = nil) {
            self.attackAdd = attackAdd
            self.attackMul = attackMul
            self.affinityAdd = affinityAdd
            self.critMultiplier = critMultiplier
        }

        static func atk(_ v: Int) -> Effect { Effect(attackAdd: v) }
        static func aff(_ v: Int) -> Effect { Effect(affinityAdd: v) }
        static func mul(_ v: Double) -> Effect { Effect(attackMul: v) }
        static func crit(_ v: Double) -> Effect { Effect(critMultiplier: v) }
        public static let none = Effect()
    }

    /// 連撃の効果が武器種で変わるための区分
    public enum WeaponGroup: Sendable {
        case heavy   // 大剣・狩猟笛
        case blade   // その他剣戟系
        case ranged  // ボウガン・弓

        public init(kind: String?) {
            switch kind {
            case "great-sword", "hunting-horn": self = .heavy
            case "bow", "light-bowgun", "heavy-bowgun": self = .ranged
            default: self = .blade
            }
        }
    }

    /// 定数表の1スキル分。`effects`のキーnil=常時発動
    public struct SkillEntry: Sendable {
        public let id: SkillId
        public let effects: [Condition?: [Effect]]   // 値はLv1からの配列
        /// 連撃だけ武器種別の表を持つ
        public let burstByGroup: [WeaponGroup: [Effect]]?
        /// 効果文(マスタ)に数値が書かれているか(テストで突合する対象)
        public let sourcedFromMaster: Bool

        init(_ id: SkillId, _ effects: [Condition?: [Effect]], burstByGroup: [WeaponGroup: [Effect]]? = nil, sourcedFromMaster: Bool = true) {
            self.id = id
            self.effects = effects
            self.burstByGroup = burstByGroup
            self.sourcedFromMaster = sourcedFromMaster
        }

        public var conditions: [Condition] {
            Condition.allCases.filter { effects.keys.contains($0) }
        }

        func effect(level: Int, condition: Condition?, weaponGroup: WeaponGroup) -> Effect? {
            guard level > 0 else { return nil }
            if condition == .burst, let table = burstByGroup?[weaponGroup] {
                return table[min(level, table.count) - 1]
            }
            guard let levels = effects[condition], !levels.isEmpty else { return nil }
            return levels[min(level, levels.count) - 1]
        }
    }

    // MARK: - スキルID(マスタgame_id)

    public enum SkillIds {
        public static let attackBoost: SkillId = 1
        public static let criticalEye: SkillId = -2096489472
        public static let criticalBoost: SkillId = -1607763456
        public static let weaknessExploit: SkillId = -397570464
        public static let agitator: SkillId = 1865909632
        public static let latentPower: SkillId = 1763191040
        public static let maximumMight: SkillId = 632127488
        public static let adrenalineRush: SkillId = 1174975744
        public static let peakPerformance: SkillId = 2106877312
        public static let resentment: SkillId = 1359821952
        public static let heroics: SkillId = 422666624
        public static let offensiveGuard: SkillId = -181127504
        public static let ambush: SkillId = -171796848
        public static let counterstrike: SkillId = 280489184
        public static let criticalDraw: SkillId = 686533440
        public static let punishingDraw: SkillId = -1946345856
        public static let antivirus: SkillId = -1662120192
        public static let foray: SkillId = 27684744
        public static let slickedBlade: SkillId = -847539392
        public static let ebonyOdogaronsPower: SkillId = 918165056
        public static let doshagumasMight: SkillId = -62248528
        public static let xuWusVigor: SkillId = -1468066176
        public static let burst: SkillId = 565867136
        public static let goreMagalasTyranny: SkillId = 722735744
        public static let leviathansFury: SkillId = 16835
        public static let omegaResonance: SkillId = 31540
        public static let tetradShot: SkillId = 1613139840
        public static let lordsFavor: SkillId = -1769550080
        public static let lordsSoul: SkillId = 1484575872
        public static let lordsFury: SkillId = 2107855744
        public static let butteryLeathercraft: SkillId = 451472896
        public static let fortifyingPelt: SkillId = 1998066176
        public static let jinDahaadsRevolt: SkillId = -215826112
        public static let blangongasSpirit: SkillId = 741102208
        public static let blossomdancePrayer: SkillId = -911441792
        public static let flamefetePrayer: SkillId = 8694
        public static let dreamspellPrayer: SkillId = 11709
        public static let lumenhymnPrayer: SkillId = 30815
        public static let seregiossTenacity: SkillId = 30992
        public static let powerStone: SkillId = 28385
    }

    /// 狂竜症克服中はスキルの有無に関係なく会心+15%(ゲーム仕様)
    public static let frenzyOvercomeAffinity = 15

    // MARK: - 定数表(仕様3.7。行の順序=状態別一覧の表示順)

    public static let table: [SkillEntry] = {
        typealias E = Effect
        let festival: [Condition?: [Effect]] = [.festival: [.none, .mul(1.09)]]
        return [
            // 常時発動
            SkillEntry(SkillIds.attackBoost, [nil: [.atk(3), .atk(5), .atk(7), E(attackAdd: 8, attackMul: 1.02), E(attackAdd: 9, attackMul: 1.04)]]),
            SkillEntry(SkillIds.criticalEye, [nil: [.aff(4), .aff(8), .aff(12), .aff(16), .aff(20)]]),
            SkillEntry(SkillIds.criticalBoost, [nil: [.crit(1.28), .crit(1.31), .crit(1.34), .crit(1.37), .crit(1.40)]]),
            // 条件付き(効果文に数値あり)
            SkillEntry(SkillIds.weaknessExploit, [
                .weakSpot: [.aff(5), .aff(10), .aff(15), .aff(20), .aff(30)],
                .wound: [.aff(3), .aff(5), .aff(10), .aff(15), .aff(20)],
            ]),
            SkillEntry(SkillIds.agitator, [.enraged: [
                E(attackAdd: 4, affinityAdd: 3), E(attackAdd: 8, affinityAdd: 5), E(attackAdd: 12, affinityAdd: 7),
                E(attackAdd: 16, affinityAdd: 10), E(attackAdd: 20, affinityAdd: 15)]]),
            SkillEntry(SkillIds.latentPower, [.latentPower: [.aff(10), .aff(20), .aff(30), .aff(40), .aff(50)]]),
            SkillEntry(SkillIds.maximumMight, [.maxMight: [.aff(10), .aff(20), .aff(30)]]),
            SkillEntry(SkillIds.adrenalineRush, [.adrenalineRush: [.atk(10), .atk(15), .atk(20), .atk(25), .atk(30)]]),
            SkillEntry(SkillIds.peakPerformance, [.peakPerformance: [.atk(3), .atk(6), .atk(10), .atk(15), .atk(20)]]),
            SkillEntry(SkillIds.resentment, [.resentment: [.atk(5), .atk(10), .atk(15), .atk(20), .atk(25)]]),
            SkillEntry(SkillIds.heroics, [.heroics: [.none, .mul(1.05), .mul(1.05), .mul(1.10), .mul(1.30)]]),
            SkillEntry(SkillIds.offensiveGuard, [.offensiveGuard: [.mul(1.05), .mul(1.10), .mul(1.15)]]),
            SkillEntry(SkillIds.ambush, [.ambush: [.mul(1.05), .mul(1.10), .mul(1.15)]]),
            SkillEntry(SkillIds.counterstrike, [.counterstrike: [.atk(10), .atk(15), .atk(25)]]),
            SkillEntry(SkillIds.criticalDraw, [.drawAttack: [.aff(50), .aff(75), .aff(100)]]),
            SkillEntry(SkillIds.punishingDraw, [.drawAttack: [.atk(3), .atk(5), .atk(7)]]),
            SkillEntry(SkillIds.antivirus, [.frenzyOvercome: [.aff(3), .aff(6), .aff(10)]]),
            SkillEntry(SkillIds.foray, [.foray: [
                .atk(6), E(attackAdd: 8, affinityAdd: 5), E(attackAdd: 10, affinityAdd: 10),
                E(attackAdd: 12, affinityAdd: 15), E(attackAdd: 15, affinityAdd: 20)]]),
            SkillEntry(SkillIds.slickedBlade, [
                .wet: [.aff(3), .aff(6), .aff(9)],
                .bubble: [.aff(7), .aff(14), .aff(21)],
            ]),
            SkillEntry(SkillIds.ebonyOdogaronsPower, [.burst: [.atk(8), .atk(18)]]),
            SkillEntry(SkillIds.doshagumasMight, [.counterAttack: [.atk(10), .atk(25)]]),
            SkillEntry(SkillIds.xuWusVigor, [.ateMeat: [.atk(15), .atk(30)]]),
            // 条件付き(攻略サイトの実測値。仕様3.7に出典)
            SkillEntry(SkillIds.burst, [.burst: []], burstByGroup: [
                .heavy: [.atk(10), .atk(12), .atk(14), .atk(16), .atk(18)],
                .blade: [.atk(8), .atk(10), .atk(12), .atk(15), .atk(18)],
                .ranged: [.atk(6), .atk(7), .atk(8), .atk(9), .atk(10)],
            ], sourcedFromMaster: false),
            SkillEntry(SkillIds.goreMagalasTyranny, [
                .frenzyInfected: [.none, .atk(10)],
                .frenzyOvercome: [.none, .atk(15)],
            ], sourcedFromMaster: false),
            SkillEntry(SkillIds.leviathansFury, [.leviathanFury: [.aff(15), .aff(15)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.omegaResonance, [
                .resonanceNear: [.aff(20), .aff(40)],
                .resonanceFar: [.atk(10), .atk(20)],
            ], sourcedFromMaster: false),
            SkillEntry(SkillIds.tetradShot, [.tetradShot: [.aff(8), .aff(10), .aff(12)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.lordsFavor, [.lordsFavor: [.atk(10)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.lordsSoul, [.lordsSoul: [.mul(1.05)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.lordsFury, [.lordsFury: [.atk(10)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.butteryLeathercraft, [.sliding: [.aff(30)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.fortifyingPelt, [
                .fortify1: [.mul(1.10)],
                .fortify2: [.mul(1.21)],
            ], sourcedFromMaster: false),
            SkillEntry(SkillIds.jinDahaadsRevolt, [.revolt: [.atk(25), .atk(50)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.blangongasSpirit, [.warCry: [.atk(3), .atk(6)]], sourcedFromMaster: false),
            SkillEntry(SkillIds.blossomdancePrayer, festival, sourcedFromMaster: false),
            SkillEntry(SkillIds.flamefetePrayer, festival, sourcedFromMaster: false),
            SkillEntry(SkillIds.dreamspellPrayer, festival, sourcedFromMaster: false),
            SkillEntry(SkillIds.lumenhymnPrayer, festival, sourcedFromMaster: false),
        ]
    }()

    /// 常時発動(条件なし)で計上するスキル(攻撃・見切り・超会心。定数表の順)
    public static var alwaysOnSkillIds: [SkillId] {
        table.filter { $0.effects.keys.contains(nil) }.map(\.id)
    }

    /// 効果量が確定できず未計上とするスキル(仕様3.7-8。その他の攻撃力加算で手入力)
    public static let uncountedSkillIds: [SkillId] = [SkillIds.seregiossTenacity, SkillIds.powerStone]

    public static func uncountedSkills(in skills: [SkillId: Int]) -> [SkillId] {
        uncountedSkillIds.filter { (skills[$0] ?? 0) > 0 }
    }

    // MARK: - アイテム・食事(仕様3.7 アイテム表)

    public struct ItemSelection: Sendable, Equatable, Codable {
        public enum Demondrug: String, CaseIterable, Sendable, Codable { case none, normal, mega }
        public enum Might: String, CaseIterable, Sendable, Codable { case none, seed, pill }
        public enum MoodyMeal: String, CaseIterable, Sendable, Codable { case none, small, large }

        public var powercharm = false      // 力の護符 +6
        public var demonPowder = false     // 鬼人の粉塵 +10
        public var demondrug: Demondrug = .none   // 鬼人薬 +5 / グレート +7
        public var might: Might = .none           // 怪力の種 +10 / 丸薬 +25
        public var moodyMeal: MoodyMeal = .none   // お食事ムラ気術 小+7 / 大+15

        public init() {}

        public var attackBonus: Int {
            var v = 0
            if powercharm { v += 6 }
            if demonPowder { v += 10 }
            switch demondrug { case .none: break; case .normal: v += 5; case .mega: v += 7 }
            switch might { case .none: break; case .seed: v += 10; case .pill: v += 25 }
            switch moodyMeal { case .none: break; case .small: v += 7; case .large: v += 15 }
            return v
        }
    }

    // MARK: - 計算

    public struct Input: Sendable {
        public var baseAttack: Int
        public var weaponAffinity: Int
        public var skills: [SkillId: Int]
        public var weaponKind: String?
        public var conditions: Set<Condition>
        public var items: ItemSelection
        public var extraAttack: Int
        public var extraAffinity: Int

        public init(
            baseAttack: Int, weaponAffinity: Int, skills: [SkillId: Int], weaponKind: String? = nil,
            conditions: Set<Condition> = [], items: ItemSelection = ItemSelection(),
            extraAttack: Int = 0, extraAffinity: Int = 0
        ) {
            self.baseAttack = baseAttack
            self.weaponAffinity = weaponAffinity
            self.skills = skills
            self.weaponKind = weaponKind
            self.conditions = conditions
            self.items = items
            self.extraAttack = extraAttack
            self.extraAffinity = extraAffinity
        }
    }

    public struct Output: Sendable, Equatable {
        public let attack: Int
        /// 上限適用後の会心率(−100〜100)
        public let affinity: Int
        public let isAffinityCapped: Bool
        public let critMultiplier: Double
        /// 会心込み攻撃力(期待値)
        public let expected: Double
    }

    public static func evaluate(_ input: Input) -> Output {
        let group = WeaponGroup(kind: input.weaponKind)
        var mul = 1.0
        var add = 0
        var affinity = input.weaponAffinity
        var crit: Double?
        for entry in table {
            guard let level = input.skills[entry.id], level > 0 else { continue }
            let conditions: [Condition?] = [nil] + entry.conditions.map { Optional($0) }
            for condition in conditions {
                if let c = condition, !input.conditions.contains(c) { continue }
                guard let e = entry.effect(level: level, condition: condition, weaponGroup: group) else { continue }
                mul *= e.attackMul
                add += e.attackAdd
                affinity += e.affinityAdd
                if let k = e.critMultiplier { crit = k }
            }
        }
        if input.conditions.contains(.frenzyOvercome) { affinity += frenzyOvercomeAffinity }
        add += input.items.attackBonus + input.extraAttack
        affinity += input.extraAffinity

        let attack = Int((Double(input.baseAttack) * mul).rounded(.down)) + add
        let capped = affinity > 100 || affinity < -100
        let c = max(-100, min(100, affinity))
        let k = c >= 0 ? (crit ?? 1.25) : 0.75
        let expected = Double(attack) * (1 + Double(abs(c)) / 100 * (k - 1))
        return Output(attack: attack, affinity: c, isAffinityCapped: capped, critMultiplier: k, expected: expected)
    }

    /// 増加率(%)。baseが0以下なら0
    public static func gainPercent(from base: Double, to other: Double) -> Double {
        guard base > 0 else { return 0 }
        return (other - base) / base * 100
    }

    // MARK: - 状態行(左右の和集合)

    public struct ConditionRow: Sendable, Equatable {
        public let condition: Condition
        /// この条件で効くスキル(定数表の順)。抜刀術【技】【力】のように複数になり得る
        public let skillIds: [SkillId]
    }

    /// 与えた装備(発動スキルの集合)のどれかが持つ条件付きスキルから、状態行を定数表の順に作る
    public static func rows(for skillSets: [[SkillId: Int]]) -> [ConditionRow] {
        var order: [Condition] = []
        var skillsByCondition: [Condition: [SkillId]] = [:]
        for entry in table {
            let present = skillSets.contains { ($0[entry.id] ?? 0) > 0 }
            guard present else { continue }
            for condition in entry.conditions {
                if skillsByCondition[condition] == nil { order.append(condition) }
                skillsByCondition[condition, default: []].append(entry.id)
            }
        }
        return order.map { ConditionRow(condition: $0, skillIds: skillsByCondition[$0] ?? []) }
    }
}
