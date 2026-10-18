# Marginstone

Inspired by [Varun’s Buddy](https://github.com/varun-ml/buddy). My thanks to [Varun](https://github.com/varun-ml), with delight and gratitude.

**v0.1.0 · Public Beta · macOS · Under Development**

I wanted a small app for keeping passages from whatever I happened to be reading: a book, an essay, something encountered in a browser. Marginstone keeps those passages on your Mac, with room to add a source, correct the text, and find it again later. You need neither a website nor a GitHub account.

The companions are a nautilus, a leaf, an ammonite, a brachiopod, and a fern. Fragments preserved, I suppose, although I also simply liked the idea of having one on my desk.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/companions-dark.png">
  <img src="docs/companions-light.png" width="100%" alt="Marginstone companions: Nautilus, Leaf, Ammonite, Brachiopod, Fern">
</picture>

## Using It

The companion loiters in the upper-right corner. After mouse highlighting in a supported app, it appears under your pointer. Double-click to save the passage; it returns to the corner afterward, or when you move away without saving. Keyboard highlighting does not summon it.

You can also drop text onto it, or copy text and choose **Capture clipboard** from its menu. Double-click selection capture needs permission under **System Settings → Privacy & Security → Device Control & Data Access** (**Accessibility** on older macOS versions).

Click the companion to open your collection. Click an excerpt to edit it; use **…** for source details, the original text, or deletion. **Export…** saves excerpts as Markdown. Sources are optional, and nothing is published automatically.

## Installing

Requires **macOS 13 or later** and Apple Command Line Tools.

Download and extract this repository, then run this in Terminal from its folder:

```sh
bash "Install Marginstone.command"
```

The installer builds and opens `~/Applications/Marginstone.app`. This is a source installation, not an Apple-notarised download. Updates preserve your collection; ad-hoc builds may require renewed macOS permissions.

## Website Publishing

If you use a Markdown website with a `_posts` folder, connect it in Settings. Choose **… → Add excerpt to website post…** to prepare a local draft. **Publish** is a separate, confirmed action. This feature remains experimental.

## Still Being Worked Out

Source identification and capture vary between apps. PDF text recognition can make mistakes. Please report problems with your macOS version and reading app, without including private passages or tokens.

See [Development Notes](docs/development.md) for build checks, signing, and data storage.
