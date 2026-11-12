#!/bin/bash
# Builds PR Watch and wraps it in build/PRWatch.app so macOS treats it as a real
# menu bar app (no Dock icon, can be added to Login Items).
set -euo pipefail
cd "$(dirname "$0")/.."

# The default (swift-build) backend fails with "Unknown error parsing property list"
# on Command Line Tools without Xcode, so use the older native one.
swift build -c release --build-system native
app_dir="build/PRWatch.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp .build/release/PRWatch "$app_dir/Contents/MacOS/PRWatch"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.user.prwatch</string>
  <key>CFBundleName</key><string>PR Watch</string>
  <key>CFBundleExecutable</key><string>PRWatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app_dir"
echo "Built $app_dir"
