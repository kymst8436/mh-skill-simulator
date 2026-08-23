#!/usr/bin/env bash
# mhdb-wilds-data の output/merged/ を data/source/ に取り込む取得スクリプト。
# 取得時の commit hash を data/source/SOURCE.md に記録する(引き継ぎ§4 手順1)。
set -euo pipefail

REPO_URL="https://github.com/LartTyler/mhdb-wilds-data.git"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/data/source"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> sparse clone: $REPO_URL"
git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" "$WORK_DIR/mhdb-wilds-data"
cd "$WORK_DIR/mhdb-wilds-data"
git sparse-checkout set output/merged

COMMIT_HASH="$(git rev-parse HEAD)"
COMMIT_DATE="$(git log -1 --format=%cI HEAD)"

echo "==> copy output/merged -> data/source/merged"
rm -rf "$SOURCE_DIR/merged"
mkdir -p "$SOURCE_DIR"
cp -R output/merged "$SOURCE_DIR/merged"

# ライセンス関係のファイルも参照用に保存する(Q-11)
git sparse-checkout add LICENSE README.md 2>/dev/null || true
for f in LICENSE LICENSE.md README.md; do
  if [ -f "$f" ]; then
    cp "$f" "$SOURCE_DIR/upstream-$f"
  fi
done

cat > "$SOURCE_DIR/SOURCE.md" <<EOF
# データ取得元の記録

- リポジトリ: $REPO_URL
- commit: $COMMIT_HASH
- commit日時: $COMMIT_DATE
- 取得日: $(date +%Y-%m-%d)
- 取得範囲: output/merged/ 一式(data/source/merged/ に配置)
- 取得方法: tools/fetch_source.sh(sparse clone)
EOF

echo "==> done. commit=$COMMIT_HASH"
ls "$SOURCE_DIR/merged" | head -30
