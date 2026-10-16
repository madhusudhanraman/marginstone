#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Build this application on a Mac running macOS 13 or later.' >&2; exit 1; }
xcrun --find swift >/dev/null 2>&1 || { echo 'Install Apple Command Line Tools first: xcode-select --install' >&2; exit 1; }
# Pin the traditional SwiftPM backend instead of inheriting SDK 27's new
# default backend. Use a separate cache to avoid the previous .build/out build.
args=(--build-system native --scratch-path "$PWD/.build/marginstone-native" -c release)
if [[ -n "${ARCH:-}" ]]; then
  case "$ARCH" in arm64|x86_64) ;; *) echo 'ARCH must be arm64 or x86_64' >&2; exit 1 ;; esac
  args+=(--arch "$ARCH")
fi
# Installation builds only the application. XCTest is a developer/CI dependency;
# it is not included in every standalone Command Line Tools installation.
swift build "${args[@]}" --product Marginstone
bin_path="$(swift build "${args[@]}" --product Marginstone --show-bin-path)"
app_path="$PWD/dist/Marginstone.app"
# Recreate only generated output so old bundle names cannot survive a rename.
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Marginstone" "$app_path/Contents/MacOS/Marginstone"
cp Info.plist "$app_path/Contents/Info.plist"
resource_bundle="$bin_path/Marginstone_Marginstone.bundle"
[[ -d "$resource_bundle" ]] || { echo 'Marginstone resource bundle is missing.' >&2; exit 1; }
ditto "$resource_bundle" "$app_path/Contents/Resources/Marginstone_Marginstone.bundle"
iconset="$PWD/dist/Marginstone.iconset"
mkdir -p "$iconset"
swiftc Sources/Marginstone/SystemIcons.swift scripts/render-system-icon.swift -o "$PWD/dist/render-system-icon"
"$PWD/dist/render-system-icon" Sources/Marginstone/Resources/nautilus.png "$PWD/dist/system-icon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PWD/dist/system-icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size*2))
  sips -z "$double" "$double" "$PWD/dist/system-icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/Marginstone.icns"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
echo "Built: $app_path"
