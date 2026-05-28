# clipandcue

A tiny macOS menu bar utility that remembers your last **9 clipboard copies** so you
can paste any of them back — by clicking a numbered row in the menu, or pressing
**⌘⌥V** and hitting **1–9**.

- Lives in the menu bar (no Dock icon).
- Captures **text, rich text, images, and copied files**.
- History **persists** across quit and reboot.
- **Auto-pastes** the chosen item into whatever app you were just using.
- Warns (icon flash + notification) when a copy was too large to save.
- Can **launch at login**.

## Build

Requires Xcode command line tools (Swift 5.9+).

```sh
./scripts/build_app.sh release
```

This compiles the Swift package and assembles an ad-hoc-signed `clipandcue.app`
in the project root. Move it into `/Applications`:

```sh
mv clipandcue.app /Applications/
open /Applications/clipandcue.app
```

> Installing to `/Applications` matters: macOS only lets **Launch at login**
> register reliably for an app in a stable location.

Because this is a **personal / unsigned (ad-hoc)** build, the first launch on
another Mac shows a Gatekeeper warning — right-click the app → **Open** once to
get past it. (To distribute without that warning, sign with a Developer ID and
notarize; the build script's `codesign` step is the place to swap the identity.)

## Permissions

- **Accessibility** — required to paste into other apps. The first time you pick
  an item, macOS prompts; approve clipandcue under
  *System Settings → Privacy & Security → Accessibility*. Until then, picking an
  item just places it on the clipboard for you to ⌘V manually.
- **Notifications** — used only for the "copy too large to save" alert.

## Using it

- **Click the menu bar icon** → see your last 9 copies, click one to paste.
- **⌘⌥V** → floating panel; press **1–9** to paste, **↑/↓ + ⏎** to navigate,
  **Esc** to dismiss.
- **Preferences** → launch at login, auto-paste toggle, max item size, and the
  Accessibility status.

## Previews & what's omitted

- **Text / rich text** — first line, whitespace-collapsed, truncated.
- **Images** — a thumbnail plus type and pixel size (e.g. `PNG · 1920×1080`).
- **Files** — file icon and name (`report.pdf  +2 more` for multiple).
- Empty / whitespace-only copies are ignored.
- Re-copying something already in the list **moves it to the top** (no duplicates).
- Copies larger than the size cap (default **20 MB**, set in Preferences) are
  **not saved** — you get the icon flash + notification.

## Privacy note

clipandcue is configured to **capture everything**, including clipboard items that
password managers mark as concealed/transient. That means a copied password can
land in the history and is **stored unencrypted on disk** at:

```
~/Library/Application Support/clipandcue/
  history.json     # item metadata
  blobs/           # image / rich-text data
```

Use **Clear** in the menu (or Preferences) to wipe it. The capture path is written
so that skipping concealed items, or encrypting blobs at rest, can be added later
with a small change in `ClipboardMonitor` / `ClipStore`.

## Project layout

```
Package.swift                 Swift package (executable, macOS 13+)
Sources/clipandcue/*.swift    app code
Resources/                    menu bar template icon + app icon
Info.plist                    LSUIElement (menu bar agent) bundle config
scripts/build_app.sh          build + assemble + ad-hoc sign the .app
```
