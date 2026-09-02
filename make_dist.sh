#!/bin/bash
# KageriEditor の配布用パッケージ作成スクリプト
# 使い方: ./make_dist.sh  →  dist/KageriEditor-<バージョン>.zip が生成される
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DIST_DIR="dist/KageriEditor-${VERSION}"
ZIP_PATH="dist/KageriEditor-${VERSION}.zip"

# 1. ロジックのテストを実行（失敗したら配布しない）
echo "── テストを実行 ──"
TEST_DIR=$(mktemp -d)
cp Tests/test.swift "$TEST_DIR/main.swift"
swiftc -o "$TEST_DIR/run_tests" Sources/TextLogic.swift Sources/ProofCheck.swift Sources/Outline.swift Sources/MarkdownPreview.swift "$TEST_DIR/main.swift"
"$TEST_DIR/run_tests"
rm -rf "$TEST_DIR"

# 2. クリーンビルド（ユニバーサルバイナリ）
echo "── アプリをビルド ──"
rm -rf build
./build.sh

# 3. 配布フォルダを組み立てて zip 化
echo "── パッケージを作成 ──"
rm -rf dist
mkdir -p "$DIST_DIR"
cp -R build/KageriEditor.app "$DIST_DIR/"
cp "docs/はじめにお読みください.txt" "$DIST_DIR/"

# .app のメタデータを保つため ditto で圧縮する
ditto -c -k --keepParent "$DIST_DIR" "$ZIP_PATH"

echo ""
echo "配布用パッケージができました: $ZIP_PATH"
echo "（中身: KageriEditor.app ＋ はじめにお読みください.txt）"
