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

SwiftUIでは `Color` 拡張として定義する(Assets.xcassetsに同名カラーセット)。

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
| タブバー | `mhBackgroundElevated` + 上ヘアライン。活性 `mhAccent` / 非活性 `mhTextTertiary` |
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
| `AdBannerView` | 高さ50固定・`mhBackgroundElevated`面。読み込み失敗時は高さ0に畳む |
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

## 8. 禁止事項

- 本編UIのスクリーンショット・素材・配色コードの写し取り(原則3)
- iOS標準の青(#007AFF)・標準角丸(10pt超)・影付きカードの使用
- 明朝体の本文使用、モチーフの複数使用、金色面の多用(アンバー面は主ボタンとR8バッジのみ)
- ライトモード対応(単一テーマ方針に反する)

## 9. 画面設計.mdとの関係

画面設計.md §5「共通UI規約への参照」の参照先は本書。構成要素・文言・状態は画面設計.mdが正、見た目は本書が正。矛盾に気づいたら勝手に直さずユーザーに確認する。
