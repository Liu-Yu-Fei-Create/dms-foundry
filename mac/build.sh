#!/usr/bin/env bash
# 组装一个可直接双击的 .app（不依赖 Xcode 工程）
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
APP_NAME="DMS Foundry"
APP="${APP_NAME}.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DMSFoundry" "$APP/Contents/MacOS/DMSFoundry"

# SPM 资源 bundle（Bundle.module 会在 Contents/Resources 与可执行文件旁查找）
for b in "$BIN"/*.bundle; do
  [ -e "$b" ] || continue
  cp -R "$b" "$APP/Contents/Resources/"
done

PUBKEY=""
[ -f ../server/keys/ed25519_pub.b64 ] && PUBKEY="$(cat ../server/keys/ed25519_pub.b64)"
FEED="${DSF_FEED_URL:-}"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DMS Foundry</string>
  <key>CFBundleDisplayName</key><string>DMS Foundry</string>
  <key>CFBundleIdentifier</key><string>org.dmsfoundry.app</string>
  <key>CFBundleExecutable</key><string>DMSFoundry</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>__BUILD__</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh_CN</string><string>en</string></array>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>DSFUpdateFeedURL</key><string>__FEED__</string>
  <key>DSFUpdatePublicKey</key><string>__PUBKEY__</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
VERSION="${DSF_VERSION:-$(cat VERSION 2>/dev/null || echo 0.2.0)}"
BUILD="${DSF_BUILD:-$(cat BUILD 2>/dev/null || echo 2)}"
/usr/bin/sed -i '' "s|__FEED__|$FEED|g; s|__PUBKEY__|$PUBKEY|g; s|__VERSION__|$VERSION|g; s|__BUILD__|$BUILD|g" "$APP/Contents/Info.plist"

if [ "${SIGNED_RELEASE:-0}" = "1" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  echo "==> Developer ID 签名"
  codesign --force --deep --options runtime --timestamp --sign "Developer ID Application" "$APP"
else
  echo "==> ad-hoc 签名（本机可用；他机需右键打开，自动更新为降级模式）"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> 完成：$(pwd)/$APP"
