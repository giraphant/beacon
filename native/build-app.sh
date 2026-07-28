#!/usr/bin/env bash
# Wraps the SwiftPM executable in a .app bundle. No Xcode project — SwiftPM
# builds the binary, this just adds Info.plist, icon and signature.
set -euo pipefail

cd "$(dirname "$0")"
APP="${1:-build/Beacon.app}"
# There is an `rm -rf "$APP"` below; refuse anything that is not a bundle path.
[[ "$APP" == *.app ]] || { echo "target must end in .app: $APP" >&2; exit 1; }

swift build -c release --product Beacon
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Beacon" "$APP/Contents/MacOS/Beacon"

# The icon only ever shows up on notification banners — LSUIElement means there
# is no Dock tile to put one in.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 512 512 ../assets/command-icon.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 ../assets/command-icon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Beacon</string>
  <key>CFBundleDisplayName</key><string>Beacon</string>
  <key>CFBundleIdentifier</key><string>com.inol.beacon</string>
  <key>CFBundleExecutable</key><string>Beacon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <!-- The relay is self-hosted and commonly plain HTTP on the LAN, which App
       Transport Security blocks. Scoped to local networking rather than
       NSAllowsArbitraryLoads, so the exchange endpoints stay TLS-only. -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

# Notifications and login-item registration both refuse to work on an unsigned
# bundle. Prefer a real Developer ID: an ad-hoc signature is regenerated on every
# build, so the keychain's "Always Allow" never matches the next build and the
# relay-token prompt comes back each time.
IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "$APP${IDENTITY:+ (signed: $IDENTITY)}"
