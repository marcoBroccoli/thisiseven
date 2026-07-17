#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

build_only=false
if [[ "${1:-}" == "--build-only" ]]; then
  build_only=true
fi

swift build -c debug --product HouseholdCommandCenter
bin_dir="$(swift build -c debug --show-bin-path)"

app_dir=".build/HouseholdCommandCenter.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

rm -rf "$app_dir"
mkdir -p "$macos_dir"
cp "$bin_dir/HouseholdCommandCenter" "$macos_dir/HouseholdCommandCenter"

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>HouseholdCommandCenter</string>
  <key>CFBundleIdentifier</key>
  <string>local.household-command-center</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Household Command Center</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$app_dir" >/dev/null 2>&1 || true
fi

if [[ "$build_only" == true ]]; then
  echo "$PWD/$app_dir"
else
  pkill -x HouseholdCommandCenter >/dev/null 2>&1 || true
  sleep 0.5
  open -n "$PWD/$app_dir"
fi
