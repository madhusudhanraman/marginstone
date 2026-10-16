# Marginstone

**v0.1.0 · Public beta · macOS**

I wanted a small app for keeping passages from whatever I happened to be reading: a book, an essay, something encountered in a browser. Copying the words is easy enough. Remembering where they came from, and finding them again a few weeks later, is less straightforward.

Marginstone is an attempt to make this a little easier. A small companion sits on your screen; drop a passage onto it, or copy the passage and choose **Capture clipboard** from its menu. The words are saved on your Mac. You can add a source, correct the text, and return to it later. You do not need a website or a GitHub account to use it.

The companions are fossils: a nautilus, a leaf, an ammonite, a brachiopod, and a fern. The connection is perhaps fairly obvious—fragments preserved, something to return to—but I also simply liked the idea of having one of these on my desk.

<table width="100%">
<tr>
<td width="20%" align="center"><img src="Sources/Nautilus/Resources/nautilus.png" width="110" alt="Nautilus"><br>Nautilus</td>
<td width="20%" align="center"><img src="Sources/Nautilus/Resources/leaf.png" width="110" alt="Leaf"><br>Leaf</td>
<td width="20%" align="center"><img src="Sources/Nautilus/Resources/ammonite.png" width="110" alt="Ammonite"><br>Ammonite</td>
<td width="20%" align="center"><img src="Sources/Nautilus/Resources/brachiopod.png" width="110" alt="Brachiopod"><br>Brachiopod</td>
<td width="20%" align="center"><img src="Sources/Nautilus/Resources/fern.png" width="110" alt="Fern"><br>Fern</td>
</tr>
</table>

## A work in progress

This is an early public version, shared while it is still being developed. The intention is a quiet, useful app for everyday reading. The interface and the details of that workflow are still being worked out.

The app has been built and run on an Apple Silicon Mac. Automated checks cover capture parsing, source metadata, editing, export, duplicate handling, and publication into temporary Git repositories. Browser-bookmark logic has also been tested in WebKit. That is not the same as having tested every combination of browser, book, and macOS version. Broader testing, particularly in Safari, Chrome, and Books, is still needed.

There is no signed, notarised release installer yet. Website publishing is experimental. Please keep separate copies of material that matters to you.

## Installing

You need a Mac running **macOS 13 or later** and Apple Command Line Tools. This release is installed from source; it is not a ready-to-run download.

1. Download this repository using **Code → Download ZIP**, and extract it into a folder you want to keep.
2. Open Terminal and run the installer from that folder:

   ```sh
   bash "Install Marginstone.command"
   ```

   You can also type `bash `, drag the installer file into Terminal, and press Return.
3. If the installer asks for Apple Command Line Tools, complete Apple's installation and run it again.

The installer builds Marginstone, places it in `~/Applications/Marginstone.app`, and opens it. Updates preserve the saved collection. Local development builds use ad-hoc signing, so macOS may ask again for folder permission after an update. Intel builds have not yet been verified on an Intel Mac.

## Using it

Drop selected text onto the companion. If dragging is unavailable, copy the passage and choose **Capture clipboard** from the companion's menu. Captures are saved automatically, even when their source is unknown.

Click an excerpt to edit it. Its **…** menu lets you add source details, inspect the original, or delete it. The dropdown filters the collection by source; it does not choose a destination for everything you capture. **Save to file…** exports the current selection as Markdown: all excerpts, or just those from the selected source.

In Settings, choose a companion and whether it moves side to side. Drag it to place it at a different height, or turn movement off to leave it where you put it.

For browser articles, **Settings → Set up browser capture…** explains how to add a capture bookmark. This can pass the selected text, page title, link, and an available author directly from the open page. Ordinary copying may supply only the selected words. Some sites block automatic metadata lookup, and not every visible byline is marked in a way the app can recognise; missing details remain editable. Books citations are likewise used when the source app supplies them.

## Optional website publishing

Marginstone can also prepare excerpts for a Markdown website with a `_posts` folder. This grew out of my own workflow, and remains the least general part of the app. It is not a universal publishing tool.

Choose your local website checkout in Settings. Marginstone prepares posts in a separate local draft branch and worktree. To review a post, use **… → Edit website post…** on an assigned excerpt. Saving an edit stays local; **Publish** is a separate, confirmed action that commits and pushes to the configured website branch. There are no automatic draft uploads.

GitHub connection uses your existing Git credentials, or a repository-scoped token stored in macOS Keychain. A failed push can leave a local commit to review in your Git client. Use a disposable website repository for testing this feature, not your live site.

## Your data

The collection is stored locally in `~/Library/Application Support/Nautilus/`. The old folder name is retained so updates continue to find existing captures. Removing the app does not remove that collection.

There is no background clipboard monitoring. Clipboard capture happens when you request it. Source lookup sends a webpage URL to that site; book searches send title and author queries to Open Library and cover searches may also use Goodreads. These requests do not send your excerpt text. Choosing Publish sends the post to your website repository.

## Development and feedback

Marginstone is written in Swift, using AppKit and SwiftUI. Some internal target names still say Nautilus, its earlier name.

```sh
bash scripts/build-macos.sh
python3 scripts/test-repository.py
python3 scripts/test-build-flow.py
bash scripts/test-core.sh
```

The Python repository tests use temporary repositories. The core checks use generated passages, not your collection. With a full Xcode installation, `swift test` runs the XCTest suite as well; XCTest is not required by the installer.

If something goes wrong, please open an issue with your macOS version, the browser or reading app involved, and what you expected to happen. A small reproducible example is especially useful. Please leave private excerpts, access tokens, and personal file paths out of reports.
