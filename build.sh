#!/bin/bash
# KageriEditor のビルドスクリプト
# 使い方: ./build.sh  →  build/KageriEditor.app が生成される
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="KageriEditor"
BUNDLE="build/KageriEditor.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

# Apple Silicon / Intel 両対応のユニバーサルバイナリを macOS 12 以降向けにビルド
swiftc -O \
    -module-name KageriEditor \
    -target arm64-apple-macos12.0 \
    -o "$BUNDLE/Contents/MacOS/$APP_NAME.arm64" \
    Sources/TextLogic.swift \
    Sources/HelpContent.swift \
    Sources/DocumentSafety.swift \
    Sources/ToolbarMenu.swift \
    Sources/SearchMatchList.swift \
    Sources/main.swift
swiftc -O \
    -module-name KageriEditor \
    -target x86_64-apple-macos12.0 \
    -o "$BUNDLE/Contents/MacOS/$APP_NAME.x86_64" \
    Sources/TextLogic.swift \
    Sources/HelpContent.swift \
    Sources/DocumentSafety.swift \
    Sources/ToolbarMenu.swift \
    Sources/SearchMatchList.swift \
    Sources/main.swift
lipo -create \
    "$BUNDLE/Contents/MacOS/$APP_NAME.arm64" \
    "$BUNDLE/Contents/MacOS/$APP_NAME.x86_64" \
    -output "$BUNDLE/Contents/MacOS/$APP_NAME"
rm "$BUNDLE/Contents/MacOS/$APP_NAME.arm64" "$BUNDLE/Contents/MacOS/$APP_NAME.x86_64"

cp Info.plist "$BUNDLE/Contents/Info.plist"

# アプリアイコン（再生成するには: swift scripts/make_icon.swift）
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# ローカル実行用のアドホック署名
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "ビルド完了: $BUNDLE"
echo "起動するには: open \"$BUNDLE\""
