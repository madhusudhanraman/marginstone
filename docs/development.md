# Development Notes

Marginstone uses Swift, AppKit, SwiftUI, PDFKit, and Vision. Native builds have been run on Apple Silicon; Intel builds have not been tested on an Intel Mac.

## Checks

```sh
bash scripts/build-macos.sh
bash scripts/test-core.sh
bash scripts/test-native-capture.sh
python3 scripts/test-repository.py
python3 scripts/test-build-flow.py
```

With full Xcode installed, `swift test` also runs XCTest. The installer does not require XCTest. Regression checks use generated fixtures, temporary Git repositories, disposable pasteboards, and hidden windows; they do not save test excerpts to the collection or publish to a website.

## Local Signing

Builds reuse a valid **Marginstone Local Development** code-signing identity from Keychain when available. Set `MARGINSTONE_SIGNING_IDENTITY` to choose another identity. Otherwise builds use ad-hoc signing, which can invalidate macOS permissions after updates. Certificate creation and trust are separate manual setup steps; the build does not create keys or change trust settings. No signing private key is included in this repository.

## Data and Permissions

Collections are stored in `~/Library/Application Support/Marginstone/`. Earlier installations retain their `Nautilus` data folder to preserve captures and Git worktree metadata. Removing the application does not remove this data.

Mouse-selection gestures can trigger an Accessibility check to position the companion. Selection capture reads highlighted text or asks the active app to Copy, and rejects an unchanged clipboard. Preview also has a mouse-drag positioning fallback. Clipboard screenshots are not automatically recognised as excerpts. PDF data and embedded attachments can be recognised on-device; recognition is imperfect.

There is no background clipboard monitoring. Source lookups contact the source website; book and cover searches contact Open Library or Goodreads. Excerpt text is not sent with those lookups. GitHub tokens are stored in macOS Keychain. Publishing explicitly commits and pushes to the configured website branch; local capture and source assignment do not publish.

## Mission Control

The companion stays visible and parks in the upper-right during Mission Control. Detection uses the Dock’s full-display overlay window metadata, not screen images. This behaviour may need adjustment if macOS changes its overview implementation.
