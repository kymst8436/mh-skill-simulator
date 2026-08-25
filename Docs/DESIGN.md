# DESIGN.md — MHシミュレーター デザイン規約

> 2026-08-24制定。方向性は「**狩猟ダーク・ミニマル**」(デザイン方向案A案をミニマルに整理したもの。ユーザー決定)。
> 実装時はこの規約に従う。画面設計.mdで個別指定していない見た目はすべて本書が既定。

## 1. 原則

1. **世界観は色と書体で出す。装飾で出さない。** 暗い墨色+アンバー+明朝体見出しで「狩猟の空気感」を作り、枠飾り・テクスチャ・グラデーションには頼らない
2. **装飾モチーフは1領域に1つまで。** 菱形モチーフ(◇)はナビゲーションタイトル横のみ。ボタンやカードには置かない
3. **ゲームUIの直接模倣をしない(権利原則)。** 本編UIのスクリーンショット・配色・枠形状・フォントの写し取りは禁止。「想起させる独自デザイン」に留める
4. **ダーク単一テーマ。** ライトモードは提供しない(`preferredColorScheme(.dark)` 固定)。OS設定に関わらず同一の見た目
5. 影は使わない(全面フラット)。階層は背景色の明度差とヘアラインで表現する

## 2. カラートークン

SwiftUIでは `Color` 拡張としてコード定義する(単一テーマのためAssets.xcassetsのカラーセットは使わない)。実装の正は `app/MHSimulator/Sources/DesignSystem/MHTheme.swift`。本書と実装がずれた場合は本書が正。

| トークン | 値 | 用途 |
|---|---|---|
| `mhBackground` | `#14120D` | 画面背景(温かみのある墨色) |
| `mhBackgroundElevated` | `#191712` | ナビバー・タブバー・シート背景 |
| `mhSurface` | `#1E1B14` | カード・リスト行の面 |
| `mhSurfaceSubtle` | `#24211A` | 入力欄・セグメント台座・ディム面 |
| `mhHairline` | `#3A342A` | 罫線・カード枠(1px) |
| `mhHairlineFaint` | `#2A2620` | リスト行間セパレータ |
| `mhTextPrimary` | `#EDE6D4` | 本文・主要テキスト(生成りの白) |
| `mhTextSecondary` | `#A89F87` | 補助テキスト |
| `mhTextTertiary` | `#6F675A` | 淡色テキスト・無効状態・プレースホルダ |
| `mhAccent` | `#D9A036` | アンバー。主ボタン・選択状態・リンク・タブ活性 |
| `mhAccentSoft` | `#E3C87F` | 条件スキルチップの文字等、アンバーの弱表現 |
| `mhAccentDim` | `#8A6F30` | アンバー系の枠線 |
| `mhOnAccent` | `#1A1204` | アンバー面上の文字 |
| `mhAccentWash` | `rgba(217,160,54,0.10)` | 選択行の背景ウォッシュ |
| `mhDestructive` | `#C25B4A` | 削除・エラー(彩度を抑えた赤) |
| `mhTitleGold` | `#E8D9A8` | 明朝見出し専用の淡金 |

### レア度色 `mhRarity(_ rarity: Int)`

| レア度 | 値 | | レア度 | 値 |
|---|---|---|---|---|
| R1 | `#8F8A7E` | | R5 | `#5B8FC2` |
| R2 | `#A9A395` | | R6 | `#9678C8` |
| R3 | `#6FA36B` | | R7 | `#C46A5A` |
| R4 | `#5FA898` | | R8 | `#D9A036` |

※独自定義の色相ランプ(緑→青→紫→赤→金)。ゲーム内配色の正確な再現はしない(原則3)。

## 3. タイポグラフィ

| 名前 | 定義 | 用途 |
|---|---|---|
| `MHFont.screenTitle` | Hiragino Mincho ProN W6 / 17pt / tracking 1.5 / `mhTitleGold` | ナビゲーションタイトル |
| `MHFont.statNumber` | Hiragino Mincho ProN W6 / 24pt / `mhTextPrimary` | 防御力等の主要数値 |
| `MHFont.button` | Hiragino Mincho ProN W6 / 17pt / tracking 3 / `mhOnAccent` | 主ボタンのラベルのみ |
| 本文 | システムフォント(SF+ヒラギノ角ゴ) 17pt | リスト行・入力 |
| 副文 | 同 15pt / `mhTextSecondary` | 補足・スロット記号 |
| キャプション | 同 13pt / `mhTextSecondary`、12pt tracking 1 はセクション見出し | セクションラベル・注記 |
| バッジ | 同 11pt bold | Rバッジ・★条件 |

- 明朝体は**上記3箇所限定**。本文に明朝を使わない(ミニマル原則)
- Dynamic Type対応: `Font.custom(_:size:relativeTo:)` で相対指定する(仕様6.4)

## 4. 形状・レイアウト

| 事項 | 決定 |
|---|---|
| 角丸 | カード・ボタン・バッジすべて **2pt**(ほぼ直角。iOS標準の10〜14ptは使わない) |
| カード枠 | `mhSurface` 面 + `mhHairline` 1px枠 |
| 余白 | 8ptグリッド。画面左右16、カード内14〜16、セクション間20 |
| セパレータ | `mhHairlineFaint` 1px、左インセット16 |
| 影・グラデーション | 使わない |
| セクション見出し | 12pt tracking 1 `mhTextTertiary`、左32(インセットグループ風の位置) |
| タップ領域 | 最小44pt(リスト行は48pt基準) |
| ナビバー | `mhBackgroundElevated` + 下ヘアライン。タイトルは`MHFont.screenTitle`+左に4pt菱形(`mhAccent`) |
| ナビバーのボタン | **OS標準スタイルは使わない**(iOS 26のガラスカプセルが角丸規約と衝突するため。2026-08-24改訂)。テキストは`MHToolbarButton`(無地・`mhAccent`)、戻るは`MHBackButton`(無地シェブロン)で統一 |
| タブバー | **OS標準TabBarは使わない**(浮遊カプセル形状のため。2026-08-24改訂)。`MHTabBar`(全幅フラット・`mhBackgroundElevated`+上ヘアライン)。活性 `mhAccent` / 非活性 `mhTextTertiary` |
| 広告バナー | 各タブの**ナビバー直下・本文の上**に固定(2026-08-24改訂。検索タブ・護石タブのみ。情報タブには置かない)。読み込み失敗時は畳む |
| シート | `mhBackgroundElevated`。グラバーは `mhHairline` |

## 5. 共通コンポーネント(SwiftUI実装名)

| コンポーネント | 見た目・仕様 |
|---|---|
| `MHCard` | mhSurface面+mhHairline枠+角丸2。内包パディング14 |
| `MHPrimaryButton` | mhAccent面・高さ50・角丸2・`MHFont.button`。無効時はopacity 0.35 |
| `MHListRow` | 高さ≥48・左右16。開閉行は右端にシェブロン(`mhTextTertiary`) |
| `SkillChip` | 枠1px角丸2・11〜13pt。条件スキル: `mhAccentDim`枠+`mhAccentSoft`文字 / その他: `mhHairline`枠+`mhTextSecondary`文字。塗りなし |
| `RarityBadge` | `mhRarity(n)`面+`#14120D`文字+「R\(n)」bold・角丸2 |
| `SlotLabel` | ①②③表記(画面設計§6の記号規約)。`mhTextSecondary` |
| `ConditionBadge` | 「★条件」。`mhAccentWash`面+`mhAccentSoft`文字 |
| `MHSectionHeader` | §4のセクション見出し。右端にアクション(「+ 追加」等 `mhAccent`)を置ける |
| `MHEmptyState` | アイコン(`mhTextTertiary`)+見出し15pt+誘導文13pt+主アクション。ContentUnavailableViewは使わず自前(トーン統一のため) |
| `AdBannerView` | 高さ50固定・`mhBackgroundElevated`面・下ヘアライン。ナビバー直下に配置し、読み込み失敗時は高さ0に畳む。タブごとの広告ユニットIDを引数で受ける |
| `MHToolbarButton` | ナビバー用テキストボタン(ToolbarContent)。無地・`mhAccent`・無効時opacity 0.35。iOS 26ではガラスカプセルを無効化する |
| `MHBackButton` | カスタム戻るボタン(無地シェブロン`mhAccent`)。標準戻るは使わない。スワイプバックは維持する |
| `MHTabBar` | 自作タブバー。全幅・上ヘアライン・アイコン24pt+ラベル10pt。選択中 `mhAccent` |
| `MHStepper` | −/+の正方ボタン(30pt・`mhHairline`枠)。iOS標準Stepperは使わない |

選択状態の行: 背景 `mhAccentWash` + チェックマーク `mhAccent`。

## 6. 状態表現

| 状態 | 表現 |
|---|---|
| 無効 | opacity 0.35(色替えではなく透過で統一) |
| 実行中 | ProgressView(`mhAccent` tint)。ボタン内では文字をProgressViewに差し替え |
| エラー文言 | `mhDestructive` 文字。枠は変えない |
| 破壊的操作 | confirmationDialogの標準UI(ここはOS標準のまま。カスタムしない) |

## 7. アイコン

- SFシンボル+線画SVG(1.5〜2pt stroke)。絵文字は使わない
- 耐性表示は「火 水 雷 氷 龍」のテキスト+属性色(火`#C25B4A` 水`#5B8FC2` 雷`#C9A227` 氷`#5FA8C2` 龍`#9678C8`)
- ゲーム抽出アイコン(スキル系統・装飾品・武器種)はPhase 5-2で導入。導入までは上記テキスト表現

## 7.5 モーション(画面遷移の入場。2026-08-24追加)

- 画面遷移(push/pop・タブ切替・sheet表示)時、**広告(バナー・ネイティブ)を除く**表示UI要素は**上から順に右からフェードイン**して現れる
- 実装は `mhEntrance(_ index:)`(DesignSystem/Components.swift)。index順に0.06sずつ遅延、easeOut 0.28s、右24pt→0+opacity 0→1
- 流す単位は**セクション単位でよい**(描画負荷を上げない。一覧はコンテナごと1単位。カード1枚ずつのstaggerは不要)
- 広告(AdBannerView・NativeAdSlot)には適用しない(即時表示)
- 新しい画面を追加するときは必ず各セクションに `mhEntrance` を付ける

## 8. 禁止事項

- 本編UIのスクリーンショット・素材・配色コードの写し取り(原則3)
- iOS標準の青(#007AFF)・標準角丸(10pt超)・影付きカードの使用
- OS標準のタブバー・ツールバーボタン・ガラス(Liquid Glass)面の使用(2026-08-24改訂。角丸と質感の統一を壊すため。`MHTabBar`/`MHToolbarButton`/`MHBackButton`を使う)
- 明朝体の本文使用、モチーフの複数使用、金色面の多用(アンバー面は主ボタンとR8バッジのみ)
- ライトモード対応(単一テーマ方針に反する)

## 9. 画面設計.mdとの関係

画面設計.md §5「共通UI規約への参照」の参照先は本書。構成要素・文言・状態は画面設計.mdが正、見た目は本書が正。矛盾に気づいたら勝手に直さずユーザーに確認する。

## 10. 実装ルール(Claude Code向け運用)

UI実装の全タスクは以下の手続きで進める。**世界観の劣化は1画面の逸脱から始まる**ため、例外を作らない。

1. **UIコードを書く前に本書を必読する**(セッションをまたいだら読み直す)
2. トークン・共通コンポーネントを**先に**実装する(`DesignSystem/MHTheme.swift`・`DesignSystem/Components/`)。画面実装がリテラル値を書き始めてからの後付けはしない
3. 逸脱(新しい色・角丸・フォント・モチーフ・アニメーション)が必要になったら、**実装せずユーザーに確認**し、承認されたら本書を先に改訂してから実装する。決定ログにも残す
4. モック(design/mockups/ のカンバス)と実機の見た目が乖離したら、モック側を直すのではなくどちらが正か確認する

### 画面実装ごとのセルフチェックリスト

- [ ] 色は `mh*` トークンのみ。リテラル色・`.blue`・`.accentColor`・`#007AFF` を使っていない
- [ ] 角丸は2pt。影・グラデーション・マテリアル(blur)を使っていない
- [ ] 明朝体は `MHFont.screenTitle` / `statNumber` / `button` の3箇所以外に使っていない
- [ ] 菱形モチーフはナビタイトル横のみ。新しい装飾を足していない
- [ ] `List`/`Form` の標準背景を消して `mhBackground` に差し替えた(`.scrollContentBackground(.hidden)`)
- [ ] ダーク固定はルート(`MHSimulatorApp`)の `preferredColorScheme(.dark)` 一括指定。画面側で再指定していない
- [ ] タップ領域44pt以上、フォントは `relativeTo:` 付きでDynamic Type対応
- [ ] 文言は画面設計.mdのものをそのまま使用(勝手に言い換えない)
- [ ] レア度表示は `RarityBadge`、スロットは `SlotLabel`、チップは `SkillChip` を使った(画面ローカルの再実装をしていない)

### MHTheme.swift の基準実装

トークンの実装はこの形とする(値は§2・§3が正)。

```swift
import SwiftUI

extension Color {
    init(mhHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
    static let mhBackground = Color(mhHex: 0x14120D)
    static let mhBackgroundElevated = Color(mhHex: 0x191712)
    static let mhSurface = Color(mhHex: 0x1E1B14)
    static let mhSurfaceSubtle = Color(mhHex: 0x24211A)
    static let mhHairline = Color(mhHex: 0x3A342A)
    static let mhHairlineFaint = Color(mhHex: 0x2A2620)
    static let mhTextPrimary = Color(mhHex: 0xEDE6D4)
    static let mhTextSecondary = Color(mhHex: 0xA89F87)
    static let mhTextTertiary = Color(mhHex: 0x6F675A)
    static let mhAccent = Color(mhHex: 0xD9A036)
    static let mhAccentSoft = Color(mhHex: 0xE3C87F)
    static let mhAccentDim = Color(mhHex: 0x8A6F30)
    static let mhOnAccent = Color(mhHex: 0x1A1204)
    static let mhAccentWash = Color(mhHex: 0xD9A036).opacity(0.10)
    static let mhDestructive = Color(mhHex: 0xC25B4A)
    static let mhTitleGold = Color(mhHex: 0xE8D9A8)

    static func mhRarity(_ rarity: Int) -> Color {
        switch rarity {
        case ...1: Color(mhHex: 0x8F8A7E)
        case 2: Color(mhHex: 0xA9A395)
        case 3: Color(mhHex: 0x6FA36B)
        case 4: Color(mhHex: 0x5FA898)
        case 5: Color(mhHex: 0x5B8FC2)
        case 6: Color(mhHex: 0x9678C8)
        case 7: Color(mhHex: 0xC46A5A)
        default: Color(mhHex: 0xD9A036)  // R8
        }
    }
}

enum MHFont {
    static let screenTitle = Font.custom("HiraMinProN-W6", size: 17, relativeTo: .headline)
    static let statNumber = Font.custom("HiraMinProN-W6", size: 24, relativeTo: .title2)
    static let button = Font.custom("HiraMinProN-W6", size: 17, relativeTo: .headline)
}
```

※「HiraMinProN-W6」はiOS同梱のヒラギノ明朝のPostScript名。実機で解決できない場合は `UIFont.familyNames` で確認して本書を更新する(勝手に別フォントへフォールバックしない)。
