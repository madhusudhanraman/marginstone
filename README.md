# Marginstone

Inspired by [Varun’s Buddy](https://github.com/varun-ml/buddy). My thanks to [Varun](https://github.com/varun-ml), with delight and gratitude.

**v0.1.0 · Public Beta · macOS**

I wanted a small app for keeping passages from whatever I happened to be reading: a book, an essay, something encountered in a browser. Copying the words is easy enough. Remembering where they came from, and finding them again a few weeks later, is less straightforward.

Marginstone is an attempt to make this a little easier. A small companion sits on your screen; drop a passage onto it, or highlight text in a supported app and double-click the companion. You can also copy a passage and choose **Capture clipboard** from its menu. The words are saved on your Mac. You can add a source, correct the text, and return to it later. You do not need a website or a GitHub account to use it.

The companions are fossils: a nautilus, a leaf, an ammonite, a brachiopod, and a fern. The connection is perhaps fairly obvious—fragments preserved, something to return to—but I also simply liked the idea of having one of these on my desk.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/companions-dark.png">
  <img src="docs/companions-light.png" width="100%" alt="Marginstone companions: Nautilus, Leaf, Ammonite, Brachiopod, Fern">
</picture>

## A Work in Progress

This is an early public version, shared while it is still being developed. The intention is a quiet, useful app for everyday reading. The interface and the details of that workflow are still being worked out.

The app has been built and run on an Apple Silicon Mac. Automated checks cover capture parsing, source metadata, editing, export, duplicate handling, and publication into temporary Git repositories. That is not the same as having tested every combination of browser, book, and macOS version. Broader testing, particularly in Safari, Chrome, and Books, is still needed.

There is no Apple-notarised release installer yet. Website publishing is experimental. Please keep separate copies of material that matters to you.

## Installing

You need a Mac running **macOS 13 or later** and Apple Command Line Tools. This release is installed from source; it is not a ready-to-run download.

1. Download this repository using **Code → Download ZIP**, and extract it into a folder you want to keep.
2. Open Terminal and run the installer from that folder:

   ```sh
   bash "Install Marginstone.command"
   ```

   You can also type `bash `, drag the installer file into Terminal, and press Return.
3. If the installer asks for Apple Command Line Tools, complete Apple's installation and run it again.

The installer builds Marginstone, places it in `~/Applications/Marginstone.app`, and opens it. Updates preserve the saved collection. Builds reuse a valid `Marginstone Local Development` signing identity from Keychain when available, or the identity set in `MARGINSTONE_SIGNING_IDENTITY`. Otherwise they use ad-hoc signing, which can require restoring macOS permissions after updates. Intel builds have not yet been verified on an Intel Mac.

## Using It

Drop selected text onto the companion. If dragging is unavailable, copy the passage and choose **Capture clipboard** from the companion's menu. To capture a selection by double-clicking, enable Marginstone in **System Settings → Privacy & Security → Device Control & Data Access** (called **Accessibility** on earlier macOS versions). Marginstone tries reading the selection, then Copy if needed. If the app does not support this, use **⌘C → Capture clipboard** from the companion’s menu. Captures are saved automatically, even when their source is unknown.

Click an excerpt to edit it. Its **…** menu lets you add source details, inspect the original, or delete it. The dropdown filters the collection by source; it does not choose a destination for everything you capture. **Export…** saves the filtered collection as Markdown: all excerpts, or just those from the selected source. Copied line wraps are reflowed for justified display; the stored original remains available.

After mouse drag-highlighting, the companion fades into place under your pointer. Keyboard selections do not move it. A successful double-click capture returns it to its previous position. If you move away without capturing, it returns there without saving anything. In Preview, this follows the end of the selection drag; other apps need to expose their selection through Accessibility.

In Settings, choose a companion and whether it wanders. Its movement changes speed and direction, with occasional pauses and small upward and downward drifts around the height where you placed it. It is smaller at rest, grows on hover and capture, and keeps its slow rotation. Drag it to choose a different resting position.

For browser articles, copy a passage or drag it onto the companion. Ordinary copying may supply only the selected words; you can add a source link, title, and author afterward. Books citations are used when the source app supplies them. Copied PDF selections can contain text, PDF data, or an embedded image; Marginstone tries the supplied text first and can recognise text locally from PDF selections and their attachments. Clipboard screenshots are not captured automatically. Scanned text can still contain recognition errors, so check it before using it elsewhere.

## Optional Website Publishing

Marginstone can also prepare excerpts for a Markdown website with a `_posts` folder. This grew out of my own workflow, and remains the least general part of the app. It is not a universal publishing tool.

Choose your local website checkout in Settings. Adding a source still only organises your local collection. To include an excerpt in a post, choose **… → Add excerpt to website post…**. Only the excerpts you select are added to the separate local draft; later captures stay in your collection. Use **Edit website post…** to return to an existing draft. Saving an edit stays local; **Publish** is a separate, confirmed action that commits and pushes to the configured website branch. There are no automatic draft uploads. Settings shows the saved website folder and the verified GitHub connection status; if folder permission expires, **Restore access** renews access to that same folder.

GitHub connection uses your existing Git credentials, or a repository-scoped token stored in macOS Keychain. A failed push can leave a local commit to review in your Git client. Use a disposable website repository for testing this feature, not your live site.

## Your Data

The collection is stored locally in `~/Library/Application Support/Marginstone/`. Earlier installations continue using their existing `Nautilus` data folder so updates retain saved captures and drafts. Removing the app does not remove that collection.

After a mouse selection gesture, Marginstone may use Accessibility to check the highlight before moving the companion; this does not save the text. There is no background clipboard monitoring. Clipboard capture happens when you request it. Source lookup sends a webpage URL to that site; book searches send title and author queries to Open Library and cover searches may also use Goodreads. These requests do not send your excerpt text. Choosing Publish sends the post to your website repository.

## Development and Feedback

Marginstone is written in Swift, using AppKit and SwiftUI. The package contains the Marginstone application, the MarginstoneCore library, and the MarginstoneCoreTests test suite.

```sh
bash scripts/build-macos.sh
python3 scripts/test-repository.py
python3 scripts/test-build-flow.py
bash scripts/test-core.sh
bash scripts/test-native-capture.sh
```

The Python repository tests use temporary repositories. The core and native checks use generated passages and disposable pasteboards, not your collection or general clipboard. Native checks cover double-click capture, PDF recognition, fading and returning to the resting position, dismissal without capture, and irregular wandering. With a full Xcode installation, `swift test` runs the XCTest suite as well; XCTest is not required by the installer.

If something goes wrong, please open an issue with your macOS version, the browser or reading app involved, and what you expected to happen. A small reproducible example is especially useful. Please leave private excerpts, access tokens, and personal file paths out of reports.
