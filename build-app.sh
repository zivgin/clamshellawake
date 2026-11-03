#!/usr/bin/env bash
# Build ClamshellAwake.app and install it to /Applications.
# Signs with Developer ID and notarizes when that identity and the notary
# profile exist (scripts/sign-notarize.sh), else ad hoc as before.
# --no-install: build and sign build/ClamshellAwake.app only.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=1; [ "${1:-}" = "--no-install" ] && INSTALL=0
SIGN=scripts/sign-notarize.sh
swift build -c release
APP=build/ClamshellAwake.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClamshellAwake "$APP/Contents/MacOS/ClamshellAwake"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.zivgin.clamshellawake</string>
  <key>CFBundleName</key><string>ClamshellAwake</string>
  <key>CFBundleExecutable</key><string>ClamshellAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
$SIGN stamp "$APP"
$SIGN sign-app "$APP" --entitlements ClamshellAwake.entitlements --fallback -
$SIGN notarize "$APP"
$SIGN verify "$APP"
[ "$INSTALL" = 1 ] || { echo "Built $APP (not installed)"; exit 0; }
rm -rf /Applications/ClamshellAwake.app
cp -R "$APP" /Applications/ClamshellAwake.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/ClamshellAwake.app
mkdir -p ~/.local/bin && cp clamshellawake ~/.local/bin/clamshellawake
echo "Installed /Applications/ClamshellAwake.app and ~/.local/bin/clamshellawake"
