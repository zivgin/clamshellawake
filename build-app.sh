#!/usr/bin/env bash
# Build Afterlid.app and install it to /Applications.
# Signs with Developer ID and notarizes when that identity and the notary
# profile exist (scripts/sign-notarize.sh), else ad hoc as before.
# --no-install: build and sign build/Afterlid.app only.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=1; [ "${1:-}" = "--no-install" ] && INSTALL=0
SIGN=scripts/sign-notarize.sh
swift build -c release
APP=build/Afterlid.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
cp .build/release/Afterlid "$APP/Contents/MacOS/Afterlid"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.zivgin.afterlid</string>
  <key>CFBundleName</key><string>Afterlid</string>
  <key>CFBundleExecutable</key><string>Afterlid</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
$SIGN stamp "$APP"
$SIGN sign-app "$APP" --entitlements Afterlid.entitlements --fallback -
$SIGN notarize "$APP"
$SIGN verify "$APP"
[ "$INSTALL" = 1 ] || { echo "Built $APP (not installed)"; exit 0; }
rm -rf /Applications/Afterlid.app
cp -R "$APP" /Applications/Afterlid.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Afterlid.app
mkdir -p ~/.local/bin && cp afterlid ~/.local/bin/afterlid
echo "Installed /Applications/Afterlid.app and ~/.local/bin/afterlid"
