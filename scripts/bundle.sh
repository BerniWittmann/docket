#!/bin/zsh
# Builds a release binary and wraps it in an ad-hoc signed Docket.app.
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Docket"
APP=Docket.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Docket"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
"$BIN" --render-icon "$ICONSET/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/icon.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# The accent colour follows the theme: n8n pink in light mode, Nord frost in dark mode.
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 15.0 --output-format human-readable-text --notices --warnings >/dev/null

# A stable identity (DOCKET_SIGN_IDENTITY) keeps Keychain and notification grants across rebuilds.
codesign --force --deep --identifier dev.berni.docket -s "${DOCKET_SIGN_IDENTITY:--}" "$APP"
echo "Built $PWD/$APP"
