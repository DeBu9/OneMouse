#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OneMouse.app"
BIN="$APP/Contents/MacOS/OneMouse"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
  -framework Cocoa -framework IOKit -framework ApplicationServices \
  src/main.swift src/AppDelegate.swift src/PointerController.swift src/ScrollController.swift src/Prefs.swift src/Diagnostics.swift \
  -o "$BIN"

cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 用固定的本地自签证书签名：designated requirement 绑定证书而不是 cdhash，
# 重编译后不会失效，辅助功能授权可以一直保留。证书不存在时退回 ad-hoc。
IDENTITY="OneMouse Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" --identifier io.local.onemouse.om --timestamp=none "$APP"
else
  echo "warning: 未找到签名证书「$IDENTITY」，退回 ad-hoc（重编译会丢失辅助功能授权）"
  codesign --force --sign - --identifier io.local.onemouse.om "$APP"
fi

echo "built: $(pwd)/$APP"
