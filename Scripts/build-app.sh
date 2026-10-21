#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export XDG_CACHE_HOME=/private/tmp/hermesmonitor-cache
export CLANG_MODULE_CACHE_PATH=/private/tmp/hermesmonitor-clang
swift build --disable-sandbox --scratch-path /private/tmp/hermesmonitor-build -c debug --product HermesMonitor
APP="$PWD/build/HermesMonitor.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp /private/tmp/hermesmonitor-build/debug/HermesMonitor "$APP/Contents/MacOS/HermesMonitor"
cp Scripts/hermes_bridge.py "$APP/Contents/Resources/hermes_bridge.py"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.hermes.monitor</string>
  <key>CFBundleName</key><string>HermesMonitor</string>
  <key>CFBundleExecutable</key><string>HermesMonitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "$APP"
