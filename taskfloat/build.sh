#!/bin/zsh
# Builds TaskFloat.app next to this script. Run it again after editing TaskFloat.swift.
set -euo pipefail
cd "$(dirname "$0")"

app=TaskFloat.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -parse-as-library -O TaskFloat.swift -o "$app/Contents/MacOS/TaskFloat"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TaskFloat</string>
  <key>CFBundleIdentifier</key><string>local.taskfloat</string>
  <key>CFBundleName</key><string>TaskFloat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app. Start it with: open $app"
