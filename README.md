# MHシミュレーター(mh-skill-simulator)

モンハンワイルズ向けiOSスキルシミュレータ。学習型プロジェクト(無料・広告なし・完全オフライン)。

- 企画・仕様・引き継ぎ: [Docs/](Docs/)(必読順: 引き継ぎ.md → プロダクト企画.md → 仕様.md)
- **進捗とタスク全体: [Docs/ロードマップ.md](Docs/ロードマップ.md)**(フェーズ構成と各タスクの状態はここが唯一の管理場所)
- 判断の原本はユーザーのObsidian vault(決定ログ)。仕様変更級の判断は勝手にしない

## データパイプライン(Phase 1)

```bash
# 1. 上流データ取得(mhdb-wilds-data のsparse clone → data/source/)
tools/fetch_source.sh

# 2. JSON→SQLite変換(data/generated/bundled.db を生成)
python3 tools/convert/convert.py

# 3. 件数・整合性検証(実測値を固定したテスト)
python3 tools/convert/test_convert.py

# 4. 鑑定護石の抽選規則を一次ソースから抽出(data/charm-rules/charm-rules.json)
#    ※ 抽出後は 2 の convert.py を再実行して規則テーブルをbundled.dbへ反映する
python3 tools/enumerate-charms/extract_rules.py

# 5. あり得る護石の全列挙(data/generated/enumerated.db。検証用・アプリ非同梱)
python3 tools/enumerate-charms/enumerate.py
```

アプリに同梱するのは bundled.db(規則テーブル込みで約0.6MB)のみ。
全列挙(約207万件・161MB)は規則検証・回帰テスト用の enumerated.db に分離している(仕様4.2、2026-08-22改訂)。

`data/source/merged/`(上流ゲームデータ)と `data/generated/`(生成物)はgit管理外。
取得元commitは `data/source/SOURCE.md` に記録され、上記手順で再現できる。

## ライセンス・クレジット(Q-11、2026-08-22決定)

- 上流 [mhdb-wilds-data](https://github.com/LartTyler/mhdb-wilds-data) はGPLv3(ツール群)。ゲームデータ自体の著作権はカプコンに帰属する前提で扱い、データはリポジトリにコミットしない
- アプリ内クレジット文面(決定済み):
  > データ: mhdb-wilds-data (LartTyler) を加工して使用
  > 本アプリは非公式であり、ゲームデータの著作権は株式会社カプコンに帰属します

## 構成

| パス | 内容 |
|---|---|
| `Docs/` | 企画書・仕様・引き継ぎ資料 |
| `data/source/` | mhdb-wilds-dataスナップショット(SOURCE.mdのみコミット) |
| `data/charm-rules/` | 鑑定護石の抽選規則(一次資産。状態はREADME参照) |
| `data/generated/` | bundled.db ほか生成物(git管理外) |
| `tools/` | 取得・変換・全列挙スクリプト(Python 3.9+、標準ライブラリのみ) |
| `app/MHSimulatorCore/` | コアロジックSwiftパッケージ(検索F-1・逆引きF-2・規則評価。Phase 2) |
| `app/` | Xcodeプロジェクト本体はPhase 3で追加(コアをローカルパッケージとして取り込む) |

## コアロジックのテスト(Phase 2)

```bash
cd app/MHSimulatorCore && swift test
```

bundled.db(上記パイプライン手順1〜2)が生成済みであること。29テストで検索・逆引き・規則評価の正しさを固定している(結果は独立検証器で再計算)。
