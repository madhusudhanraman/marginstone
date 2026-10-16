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
swift build "${args[@]}" --product Nautilus
bin_path="$(swift build "${args[@]}" --product Nautilus --show-bin-path)"
app_path="$PWD/dist/Marginstone.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Nautilus" "$app_path/Contents/MacOS/Marginstone"
cp Info.plist "$app_path/Contents/Info.plist"
for resource in "$bin_path"/*.bundle; do
  [[ -d "$resource" ]] || continue
  ditto "$resource" "$app_path/Contents/Resources/$(basename "$resource")"
done
iconset="$PWD/dist/Nautilus.iconset"
mkdir -p "$iconset"
swiftc Sources/Nautilus/SystemIcons.swift scripts/render-system-icon.swift -o "$PWD/dist/render-system-icon"
"$PWD/dist/render-system-icon" Sources/Nautilus/Resources/nautilus.png "$PWD/dist/system-icon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PWD/dist/system-icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size*2))
  sips -z "$double" "$double" "$PWD/dist/system-icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/Nautilus.icns"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
echo "Built: $app_path"
