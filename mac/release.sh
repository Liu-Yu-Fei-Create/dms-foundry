#!/usr/bin/env bash
# 构建 → 打包 → SHA-256 → Ed25519 签名 → 生成 manifest → 放到 server/<channel>/
# 用法：./release.sh <version> <build> [notes_zh] [notes_en]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?用法: release.sh <version> <build> [notes_zh] [notes_en]}"
BUILD="${2:?需要 build 号（整数，单调递增）}"
NOTES_ZH="${3:-}"
NOTES_EN="${4:-}"
CHANNEL="${CHANNEL:-stable}"
BASE_URL="${BASE_URL:-https://CHANGE-ME/dmsfoundry/$CHANNEL}"
KEY="../server/keys/ed25519.pem"

[ -f "$KEY" ] || { echo "缺少签名私钥 $KEY（先运行 openssl genpkey -algorithm ED25519 -out $KEY）"; exit 1; }

echo "==> 构建"
DSF_VERSION="$VERSION" DSF_BUILD="$BUILD" CONFIG=release ./build.sh

APP="DMS Foundry.app"
ZIP="DMSFoundry-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
SIZE="$(stat -f%z "$ZIP")"
printf '%s' "$SHA" | xxd -r -p > /tmp/dmsfoundry-digest.bin
SIG="$(openssl pkeyutl -sign -rawin -inkey "$KEY" -in /tmp/dmsfoundry-digest.bin | base64)"

mkdir -p "../server/$CHANNEL"
cp "$ZIP" "../server/$CHANNEL/$ZIP"

python3 - "$VERSION" "$BUILD" "$SHA" "$SIG" "$SIZE" "$BASE_URL" "$CHANNEL" "$NOTES_ZH" "$NOTES_EN" > "../server/$CHANNEL/manifest.json" <<'PY'
import json, sys, datetime
version, build, sha, sig, size, base, channel, zh, en = sys.argv[1:10]
m = {
  "schemaVersion": 1,
  "channel": channel,
  "latest": {
    "version": version,
    "build": int(build),
    "minOS": "14.0",
    "publishedAt": datetime.date.today().isoformat(),
    "notes": {"zh": zh or f"版本 {version}", "en": en or f"Version {version}"},
    "artifacts": [{
      "arch": "arm64",
      "url": f"{base}/DMSFoundry-{version}.zip",
      "sha256": sha,
      "signature": sig,
      "size": int(size),
    }],
  },
}
print(json.dumps(m, ensure_ascii=False, indent=2))
PY

echo "==> 产物"
echo "  $ZIP  ($SIZE bytes)"
echo "  sha256: $SHA"
echo "  manifest: server/$CHANNEL/manifest.json"
echo
echo "上传："
echo "  rsync -avz server/$CHANNEL/ <user>@<host>:/path/to/dmsfoundry/$CHANNEL/"
echo "再把 Info.plist 的 DSFUpdateFeedURL（或构建时的 DSF_FEED_URL）指向："
echo "  $BASE_URL/manifest.json"
