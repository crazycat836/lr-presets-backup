#!/bin/bash
#
# 編譯 SwiftUI app 並打包成可雙擊的 .app（不需 Xcode，只需 Command Line Tools）。
# 產出：../LR 風格檔備份.app（工具資料夾根目錄，方便雙擊）。

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(cd "$SRC_DIR/.." && pwd)"
APP_NAME="LR 風格檔備份"
BIN_NAME="LRPresetsBackup"
APP="$OUT_DIR/$APP_NAME.app"
BUILD="$SRC_DIR/.build"

echo "編譯中…"
rm -rf "$APP" "$BUILD"
mkdir -p "$BUILD"
swiftc -parse-as-library -O \
  "$SRC_DIR"/Sources/LRPresetsBackup/*.swift \
  -o "$BUILD/$BIN_NAME"

echo "打包 .app…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp "$SRC_DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ad-hoc 簽章，讓 Apple Silicon 能正常啟動、Finder 不擋
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "完成：$APP"
