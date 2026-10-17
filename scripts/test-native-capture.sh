#!/bin/bash
# Native checks use generated fixtures, hidden windows and disposable pasteboards.
set -euo pipefail
cd "$(dirname "$0")/.."
checks_dir="$(mktemp -d "${TMPDIR:-/tmp}/marginstone-native-checks.XXXXXX")"
trap 'rm -rf "$checks_dir"' EXIT
swiftc -emit-module -emit-library -module-name MarginstoneCore Sources/MarginstoneCore/*.swift -o "$checks_dir/libMarginstoneCore.dylib"
swiftc -I "$checks_dir" -L "$checks_dir" -lMarginstoneCore -Xlinker -rpath -Xlinker "$checks_dir" \
  Sources/Marginstone/Companion.swift Sources/Marginstone/CaptureReader.swift \
  Sources/Marginstone/WanderingMotion.swift Sources/Marginstone/CompanionView.swift \
  scripts/test-companion-clicks.swift -o "$checks_dir/companion"
"$checks_dir/companion"
swiftc -I "$checks_dir" -L "$checks_dir" -lMarginstoneCore -Xlinker -rpath -Xlinker "$checks_dir" \
  Sources/Marginstone/CaptureReader.swift scripts/test-pdf-capture.swift -o "$checks_dir/pdf"
"$checks_dir/pdf"
swiftc Sources/Marginstone/WanderingMotion.swift scripts/test-wandering.swift -o "$checks_dir/wandering"
"$checks_dir/wandering"
