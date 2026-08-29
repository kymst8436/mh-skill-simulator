import XCTest
@testable import MHSimulatorCore

/// 護石カメラ読み取り(F-10)の解釈規則(仕様3.6)の検証。
/// フィクスチャは2026-08-28スパイクの実写OCR結果(data/camera-samples/spike-result.md)に基づく
final class CharmScanParserTests: XCTestCase {
    let master = TestSupport.master
    var parser: CharmScanParser {
        CharmScanParser(
            skillNames: master.skills.mapValues(\.name),
            rules: master.charmRules)
    }

    /// IMG_3892相当: 秘歴の護石(攻撃Lv3/早食いLv2/体力回復量UP Lv1)。
    /// 見出しのアイコン誤読「多装備スキル」・護石外テキスト(4500z等)込み
    private var sample1: [CharmScanParser.ObservedText] {
        [
            .init(text: "装備詳細", x: 0.1, y: 0.05),
            .init(text: "L2", x: 0.2, y: 0.10),
            .init(text: "秘歴の護石", x: 0.15, y: 0.20),
            .init(text: "Lv 1/1", x: 0.1, y: 0.27),
            .init(text: "RARE 7", x: 0.6, y: 0.27),
            .init(text: "スロット", x: 0.15, y: 0.33),
            .init(text: "多装備スキル", x: 0.1, y: 0.45),
            .init(text: "攻撃", x: 0.15, y: 0.52),
            .init(text: "Lv3", x: 0.75, y: 0.55),
            .init(text: "早食い", x: 0.15, y: 0.62),
            .init(text: "Lv2", x: 0.75, y: 0.65),
            .init(text: "体力回復量UP", x: 0.15, y: 0.72),
            .init(text: "Lv1", x: 0.75, y: 0.75),
            .init(text: "4500z", x: 0.05, y: 0.90),
            .init(text: "R2", x: 0.8, y: 0.10),
        ]
    }

    private func entry(_ name: String, _ level: Int) -> CharmRules.GroupEntry {
        CharmRules.GroupEntry(skillId: TestSupport.skill(named: name).id, level: level)
    }

    func testParsesRealCharmSample() {
        let reading = parser.parse(sample1)
        // ゲーム画面のOCRは半角「UP」・DB名は全角「ＵＰ」— NFKC正規化で照合できること
        XCTAssertEqual(
            reading?.skills,
            [entry("攻撃", 3), entry("早食い", 2), entry("体力回復量ＵＰ", 1)])
        // RARE 7表記からレア度を読み取る(このスキル構成のスロット候補と整合)
        XCTAssertEqual(reading?.rarity, 7)
    }

    func testInconsistentRarityIsDropped() {
        // 規則上あり得ないレア度(RARE 1)の誤読はnilに落とす(スキルは採用)
        let items = sample1.map {
            $0.text == "RARE 7" ? CharmScanParser.ObservedText(text: "RARE 1", x: $0.x, y: $0.y) : $0
        }
        let reading = parser.parse(items)
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.skills, parser.parse(sample1)?.skills)
        XCTAssertEqual(reading?.rarity, nil)
    }

    func testRarityNilWhenNotVisible() {
        // RARE行が枠外などで読めない場合はrarity=nilで成立する
        let items = sample1.filter { $0.text != "RARE 7" }
        let reading = parser.parse(items)
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.rarity, nil)
    }

    func testParseIsOrderIndependent() {
        // 入力順はOCRの返却順に依存しない(座標で読み取り順に整列される)
        XCTAssertEqual(parser.parse(sample1.shuffled()), parser.parse(sample1))
    }

    func testParsesTwoSkillCharm() {
        // IMG_3893相当: 砲術Lv3/火耐性Lv3。右側に別パネル(ステータス)のテキストが併存
        let reading = parser.parse([
            .init(text: "秘歴の護石", x: 0.15, y: 0.20),
            .init(text: "Lv 1/1", x: 0.1, y: 0.27),
            .init(text: "装備スキル", x: 0.1, y: 0.45),
            .init(text: "砲術", x: 0.15, y: 0.52),
            .init(text: "LV3", x: 0.75, y: 0.55),
            .init(text: "火耐性", x: 0.15, y: 0.62),
            .init(text: "LV3", x: 0.75, y: 0.65),
        ])
        XCTAssertEqual(reading?.skills, [entry("砲術", 3), entry("火耐性", 3)])
    }

    func testRejectsWithoutCharmAnchor() {
        // 防具の装備詳細(「〜の護石」なし)は解釈しない
        var items = sample1.filter { $0.text != "秘歴の護石" }
        items.append(.init(text: "レダゼルトヘルムα", x: 0.15, y: 0.20))
        XCTAssertNil(parser.parse(items))
    }

    func testRejectsCountMismatch() {
        // スキル名2つ・Lv3つ(1行読めていない)は確定しない
        let items = sample1.filter { $0.text != "早食い" }
        XCTAssertNil(parser.parse(items))
    }

    func testFuzzyMatchRecoversSingleCharError() {
        // OCRの1文字誤読(早食い→早倉い)は編集距離1の唯一最小として復元される
        let items = sample1.map {
            $0.text == "早食い" ? CharmScanParser.ObservedText(text: "早倉い", x: $0.x, y: $0.y) : $0
        }
        XCTAssertEqual(parser.parse(items), parser.parse(sample1))
    }

    func testAmbiguousFuzzyMatchIsRejected() {
        // 「大耐性」は火耐性/水耐性等と等距離で唯一に絞れないため不採用→件数不一致で不成立
        let items = [
            CharmScanParser.ObservedText(text: "秘歴の護石", x: 0.15, y: 0.20),
            .init(text: "装備スキル", x: 0.1, y: 0.45),
            .init(text: "大耐性", x: 0.15, y: 0.52),
            .init(text: "Lv3", x: 0.75, y: 0.55),
        ]
        XCTAssertNil(parser.parse(items))
    }

    func testRejectsRuleInvalidLevel() {
        // 抽選規則上あり得ないレベル(攻撃Lv9)は確定しない
        let items = sample1.map {
            $0.text == "Lv3" ? CharmScanParser.ObservedText(text: "Lv9", x: $0.x, y: $0.y) : $0
        }
        XCTAssertNil(parser.parse(items))
    }

    func testLevelToken() {
        XCTAssertEqual(CharmScanParser.levelToken(CharmScanParser.normalize("Lv3")), 3)
        XCTAssertEqual(CharmScanParser.levelToken(CharmScanParser.normalize("LV1")), 1)
        XCTAssertNil(CharmScanParser.levelToken(CharmScanParser.normalize("Lv 1/1")))
        XCTAssertNil(CharmScanParser.levelToken(CharmScanParser.normalize("Lv0")))
        XCTAssertNil(CharmScanParser.levelToken(CharmScanParser.normalize("4500z")))
        // 全角英数もNFKC正規化で吸収する
        XCTAssertEqual(CharmScanParser.levelToken(CharmScanParser.normalize("Ｌｖ２")), 2)
    }

    func testEditDistanceLimit() {
        XCTAssertEqual(CharmScanParser.editDistance("火耐性", "水耐性", limit: 1), 1)
        XCTAssertNil(CharmScanParser.editDistance("火耐性", "砲術", limit: 1))
        XCTAssertEqual(CharmScanParser.editDistance("攻撃", "攻撃", limit: 1), 0)
    }

    // MARK: - 多言語プロファイル

    /// 英語画面相当: sample1と同じ護石を英語DBのスキル名+英語プロファイルで解釈できる。
    /// スキル名・護石名はハードコードせずDB(bundled.db)の英語名から組み立てる
    func testParsesEnglishSample() throws {
        let en = try MasterDatabase(path: TestSupport.bundledDbPath, language: .en)
        let parser = CharmScanParser(
            skillNames: en.skills.mapValues(\.name),
            rules: en.charmRules,
            profile: .profile(for: .en, randomCharmNames: en.randomCharmNames))
        func enName(_ ja: String) -> String { en.skills[TestSupport.skill(named: ja).id]!.name }
        let items: [CharmScanParser.ObservedText] = [
            .init(text: en.randomCharmNames[0], x: 0.15, y: 0.20),
            .init(text: "RARE 7", x: 0.6, y: 0.27),
            .init(text: "Equipped Skills", x: 0.1, y: 0.45),
            .init(text: enName("攻撃"), x: 0.15, y: 0.52),
            .init(text: "Lv3", x: 0.75, y: 0.55),
            .init(text: enName("早食い"), x: 0.15, y: 0.62),
            .init(text: "Lv2", x: 0.75, y: 0.65),
            .init(text: enName("体力回復量ＵＰ"), x: 0.15, y: 0.72),
            .init(text: "Lv1", x: 0.75, y: 0.75),
        ]
        let reading = parser.parse(items)
        XCTAssertEqual(reading?.skills, [entry("攻撃", 3), entry("早食い", 2), entry("体力回復量ＵＰ", 1)])
        XCTAssertEqual(reading?.rarity, 7)
    }

    /// 日本語アンカーのままでは英語画面は解釈されない(誤爆防止の確認)
    func testJapaneseProfileRejectsEnglishScreen() throws {
        let en = try MasterDatabase(path: TestSupport.bundledDbPath, language: .en)
        let japaneseParser = CharmScanParser(
            skillNames: en.skills.mapValues(\.name), rules: en.charmRules)
        let items: [CharmScanParser.ObservedText] = [
            .init(text: en.randomCharmNames[0], x: 0.15, y: 0.20),
            .init(text: "Equipped Skills", x: 0.1, y: 0.45),
        ]
        XCTAssertNil(japaneseParser.parse(items))
    }

    func testLocalizedTokens() {
        // フランス語: "Niv. 3" / "Rareté 7" 形式
        XCTAssertEqual(CharmScanParser.levelToken(
            CharmScanParser.normalize("Niv. 3"), prefixes: ["niv", "lv"]), 3)
        XCTAssertEqual(CharmScanParser.rarityToken(
            CharmScanParser.normalize("Rareté 7"), prefixes: ["rareté", "rare"]), 7)
        // 従来形式の互換
        XCTAssertEqual(CharmScanParser.levelToken(CharmScanParser.normalize("Lv.2")), 2)
        XCTAssertNil(CharmScanParser.levelToken(CharmScanParser.normalize("Lv 1/1")))
    }
}
