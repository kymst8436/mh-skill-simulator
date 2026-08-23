# 鑑定護石の抽選規則データ(charm-rules)

**状態: 写経済み・実物検証待ち(Q-1)** — 2026-08-21

`charm-rules.json` に、鑑定護石の抽選規則(スキルグループ・パターン・スロット)を機械可読データとして格納している。逆引き機能(F-2)・入力補助(F-3)の生命線。

## 出典と作成方法

- 一次ソース: [Nettoge — 鑑定護石の出現パターンとシミュレータ](https://nettoge.com/mhwilds-talisman-patterns-simulator/)
- `tools/enumerate-charms/extract_rules.py` がページ内のインラインJS(GROUP_SKILLS)とHTMLパターン表を**機械抽出**する(手写しではないので転記ミスは構造変化以外起きない)
- 抽出済み内容: スキルグループ10個(延べ288スキル)+パターン29行(レア度5〜8)
- 確率は取り込まない(決定済み)
- スキル名の表記揺れ: 出典は半角(KO術/UP)、ゲームデータは全角(ＫＯ術/ＵＰ)。照合はNFKC正規化で行う(enumerate.py)

## 検証状況(Q-1)

**部分検証済み(2026-08-22、ユーザー実機確認)**:

1. 同一スキルは1つの護石に重複しない → 列挙は `dup-policy=drop`(既定)で除外
2. レア度7にスロ3はあり得る → パターン表が正。ページ凡例の「スロ3はレア度5のみ」が誤り

**全体検証は未了。** 引き続きユーザーの実物護石と突き合わせ、「列挙に存在しない実物」が出たら規則データの誤りとして即報告する。検証完了まで逆引き機能は「実験的機能」扱い。

## 更新手順

```bash
python3 tools/enumerate-charms/extract_rules.py   # 実サイトから再抽出
python3 tools/enumerate-charms/enumerate.py        # bundled.dbのEnumeratedCharmを再生成
```

## 規模実測(Q-2、2026-08-22)

- 全列挙: 2,076,040件(dup-policy=drop)→ `data/generated/enumerated.db`(161MB・**アプリ非同梱**、検証・回帰テスト用)
- アプリ同梱の bundled.db は規則テーブル(CharmSkillGroup/CharmPattern)方式で約0.6MB(2026-08-22決定。仕様4.2改訂)
- 逆引きサンプルクエリ: 1ms未満
