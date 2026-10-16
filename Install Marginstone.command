#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
finish() { result=$?; if [[ $result -ne 0 ]]; then echo; echo 'Installation did not finish. Copy the error above if you need help.'; fi; echo; read -r -p 'Press Return to close…' ignored || true; }
trap finish EXIT
[[ "$(uname -s)" == Darwin ]] || { echo 'Run this installer on your Mac.' >&2; exit 1; }
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 13 ]] || { echo 'Marginstone requires macOS 13 or later.' >&2; exit 1; }
if ! xcrun --find swift >/dev/null 2>&1; then
  echo 'Marginstone needs Apple Command Line Tools to build locally.'
  echo 'Finish the Apple installer that opens, then run Install Marginstone.command again.'
  xcode-select --install || true
  exit 1
fi
if pgrep -x Nautilus >/dev/null || pgrep -x Marginstone >/dev/null; then echo 'Quit the running Marginstone app before installing an update.' >&2; exit 1; fi
bash scripts/build-macos.sh
mkdir -p "$HOME/Applications"
# Install a clean bundle; copying over the old executable name leaves stale files.
previous=""
if [[ -d "$HOME/Applications/Marginstone.app" ]]; then
  previous="$HOME/Applications/Marginstone.app"
elif [[ -d "$HOME/Applications/Nautilus.app" ]]; then
  previous="$HOME/Applications/Nautilus.app"
fi
backup="$(mktemp -d "${TMPDIR:-/tmp}/marginstone-install.XXXXXX")"
if [[ -n "$previous" ]]; then mv "$previous" "$backup/Previous.app"; fi
if ! ditto dist/Marginstone.app "$HOME/Applications/Marginstone.app" || ! codesign --verify --deep --strict "$HOME/Applications/Marginstone.app"; then
  if [[ -e "$HOME/Applications/Marginstone.app" ]]; then mv "$HOME/Applications/Marginstone.app" "$backup/Failed.app"; fi
  if [[ -n "$previous" ]]; then mv "$backup/Previous.app" "$previous"; fi
  exit 1
fi
open "$HOME/Applications/Marginstone.app"
echo 'Marginstone is installed in your Applications folder. Capture an excerpt to get started.'
