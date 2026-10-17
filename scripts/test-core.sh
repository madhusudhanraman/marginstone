#!/bin/bash
# Generated fixtures only; no app collection or website access.
set -euo pipefail
cd "$(dirname "$0")/.."
checks_dir="$(mktemp -d "${TMPDIR:-/tmp}/marginstone-core.XXXXXX")"
trap 'rm -rf "$checks_dir"' EXIT
for test in test-source-metadata test-local-export test-duplicates test-website-selection test-excerpt-layout; do
  swiftc Sources/MarginstoneCore/*.swift "scripts/$test.swift" -o "$checks_dir/$test"
  "$checks_dir/$test"
done
