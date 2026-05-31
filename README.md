# clipandcue

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC%20BY--NC%204.0-blue.svg)](LICENSE)
[![Website](https://img.shields.io/badge/site-clipandcue.com-ff9bb3.svg)](https://clipandcue.com)

**Copy now. Paste later.** A tiny macOS menu bar utility that remembers your last
**9 clipboard copies** so you can paste any of them back — by clicking a numbered
row in the menu, or pressing **⌘⌥V** and hitting **1–9**.

- Lives in the menu bar (no Dock icon).
- Captures **text, rich text, images, and copied files**.
- History **persists** across quit and reboot.
- **Auto-pastes** the chosen item into whatever app you were just using.
- **Export to Notes** — turn your history (text *and* images) into one Notes note.
- Warns (icon flash + notification) when a copy was too large to save.
- Can **launch at login**.

Website: **[clipandcue.com](https://clipandcue.com)** · Current version: **0.1.3**

---

## Install

**Easiest:** download the notarized `clipandcue.dmg` from the
[Releases page](https://github.com/mrmichaelmoorecom-sys/clipandcue/releases),
open it, and drag **clipandcue** onto **Applications**. Release builds are signed
with a Developer ID and notarized by Apple, so they open with no Gatekeeper warning.

Then launch it from `/Applications`. The icon appears in the menu bar (top-right),
not the Dock.

> Installing to `/Applications` matters: macOS only lets **Launch at login**
> register reliably for an app in a stable location.

## Build from source

Requires the Xcode command line tools (Swift 5.9+), macOS 13+.

```sh
./scripts/build_app.sh release
```

This compiles the Swift package and assembles an **ad-hoc-signed** `clipandcue.app`
in the project root (fine for personal use; Gatekeeper shows a one-time warning).
Move it into `/Applications`:

```sh
mv clipandcue.app /Applications/
open /Applications/clipandcue.app
```

To produce a **Developer ID-signed, notarized** release dmg instead, see
[Release pipeline](#release-pipeline) below.

## Permissions

- **Accessibility** — required to paste into other apps. The first time you pick
  an item, macOS prompts; approve clipandcue under
  *System Settings → Privacy & Security → Accessibility*. Until then, picking an
  item just places it on the clipboard for you to ⌘V manually.
- **Notifications** — used only for the "copy too large to save" alert.

## Using it

- **Click the menu bar icon** → see your recent copies; click one to paste.
  Footer has **Clear**, **Export**, **How to**, **Preferences**, and **Quit**.
- **⌘⌥V** → floating quick-paste panel; press **1–9** to paste, **↑/↓ + ⏎** to
  navigate, **Esc** to dismiss.
- **Pin a favorite** → click the **number badge** on a row in the menu to pin
  it. Pinned items jump to the top and stay there as you keep copying. Click the
  badge again to unpin.
- **Export** → dumps the whole history into a temp `.rtfd` document and opens
  it in TextEdit (text rows + inline image attachments). Save / share from
  there, or ⌘A ⌘C and paste into Notes / Mail.

## Preferences

- **General** — Launch at login · keep *N* recent items (1–9) · the fixed
  quick-paste shortcut (⌘⌥V).
- **Pasting** — auto-paste into the active app · paste as plain text (drops fonts
  and colors from rich-text copies).
- **Privacy & storage** — ignore items password managers flag as
  concealed/transient · clear history on quit · don't save items larger than
  *N* MB (default 20) · clear history now.
- **Permissions** — live Accessibility status + a button straight to the right
  System Settings pane.
- **About** — version, license, and links to the website / GitHub / license.

## Previews & what's omitted

- **Text / rich text** — first line, whitespace-collapsed, truncated.
- **Images** — a thumbnail plus type and pixel size (e.g. `PNG · 1920×1080`).
- **Files** — file icon and name (`report.pdf  +2 more` for multiple).
- Empty / whitespace-only copies are ignored.
- Re-copying something already in the list **moves it to the top** (no duplicates).
- Copies larger than the size cap (default **20 MB**) are **not saved** — you get
  the icon flash + notification.

## Privacy note

By default clipandcue **captures everything**, including clipboard items password
managers mark as concealed/transient. That means a copied password can land in the
history and is **stored unencrypted on disk** in your *user* Library:

```
~/Library/Application Support/clipandcue/
  history.json     # item metadata
  blobs/           # image / rich-text data
```

> Finder hides `~/Library` by default. To navigate to the folder, open Finder,
> press **⌘⇧G** (Go → Go to Folder…), paste the path, and press Return.

To harden this: turn on **Ignore items from password managers** and/or **Clear
history when I quit** in Preferences, or use **Clear** anytime. The capture path is
also written so that encrypting blobs at rest can be added later with a small change
in `ClipboardMonitor` / `ClipStore`.

## Project layout

### App (Swift package)

```
Package.swift                      Swift package — executable target, macOS 13+
Info.plist                         LSUIElement (menu bar agent), bundle id/version,
                                   Apple-events usage string for Notes export
entitlements.plist                 hardened-runtime entitlements (Apple-events) for
                                   the notarized build
Sources/clipandcue/
  main.swift                       entry point — boots the AppDelegate
  AppDelegate.swift                .accessory app, wires monitor/hotkey/status item
  AppSettings.swift                UserDefaults-backed preferences (ObservableObject)
  ClipItem.swift                   Codable model: kind (text/richText/image/files)
  ClipStore.swift                  ordered, capped store + debounced disk persistence
  ClipboardMonitor.swift           polls NSPasteboard.changeCount, applies filters
  ImageUtils.swift                 thumbnailing / image helpers
  Paster.swift                     writes item back to pasteboard + synthesizes ⌘V
  GlobalHotkey.swift               Carbon RegisterEventHotKey for ⌘⌥V
  StatusItemController.swift       NSStatusItem, popover, icon-flash warning
  QuickPasteController.swift       borderless HUD panel for 1–9 quick paste
  Notifier.swift                   UNUserNotificationCenter "too large" alert
  LaunchAtLogin.swift              SMAppService register/unregister/status
  Exporter.swift                   builds an RTFD document and opens it in TextEdit
  Views/
    MenuListView.swift             the dropdown list + footer actions
    ClipRowView.swift              one history row (badge + preview)
    QuickPasteHUDView.swift        the large ⌘⌥V panel UI
    PreferencesView.swift          settings form
    HowToView.swift                in-app "How to" walkthrough
Resources/
  AppIcon.icns                     app icon (Dock / Finder / About)
  menubarTemplate.png / @2x        the menu bar template image (auto-tints to theme)
  dmg-background.tiff              HiDPI background baked into the installer dmg
```

### Website & distribution

```
index.html                        the landing page (custom CSS + JS animations)
CNAME                              GitHub Pages custom domain (clipandcue.com)
robots.txt / sitemap.xml          SEO
img/                               brand + web assets (see below)
```

### Brand & web assets (`img/`)

| File | Purpose |
|---|---|
| `appicon_1024.png` / `appicon_256.png` | master app-icon renders (source for `AppIcon.icns`) |
| `favicon.ico` / `clipandcue_icon_only.ico` | site favicon (referenced in `index.html`) |
| `logo_stacked.svg` | logo used to render the OG share image |
| `logo_horizontal.svg` | horizontal logo variant (brand kit) |
| `mark_accent.svg` | the bare clip mark (brand kit) |
| `menubar icon.png` | source art for the `menubarTemplate` images |
| `install and web icon.png` | high-res install/web icon |
| `og-image.png` | social share preview (generated by `make_og.swift`) |
| `trmlogo.svg` | small logo used on the page |

> Some assets aren't linked from code directly — they're the **source art** the
> build scripts and icon pipeline are generated from. Keep them.

### Scripts

| Script | What it does |
|---|---|
| `scripts/build_app.sh` | `swift build` → assemble `clipandcue.app`. Ad-hoc signs by default; Developer ID + hardened-runtime signs when `CODESIGN_IDENTITY` is set. |
| `scripts/make_dmg.sh` | builds the drag-to-Applications dmg using `hdiutil` + a Finder/AppleScript layout, with the branded HiDPI background and a "Read Me" file. |
| `scripts/make_dmg_bg.swift` | renders `Resources/dmg-background.tiff` (pale-pink wash + faint clip watermark + arrow + Outfit headline) via AppKit. |
| `scripts/make_og.swift` | renders `img/og-image.png` (1200×630 social share card). |
| `scripts/notarize.sh` | full release pipeline: Developer ID sign → notarize → staple the app, build the dmg, then sign → notarize → staple the dmg. |

## Release pipeline

Release builds are **signed with a Developer ID and notarized by Apple**.

One-time setup (paid Apple Developer membership):

1. A *Developer ID Application* certificate in your login keychain.
2. A notarytool keychain profile:
   ```sh
   xcrun notarytool store-credentials "clipandcue-notary" \
     --apple-id "you@email.com" --team-id "<TEAMID>" --password "<app-specific-pw>"
   ```

Then build a notarized dmg:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="clipandcue-notary" \
./scripts/notarize.sh
```

Upload the resulting `clipandcue.dmg` as a GitHub Release asset.

**Versioning:** bump `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist`
only for code changes. Re-notarizing or re-packaging the same build reuses the same
release (replace the asset) — no version bump needed.

## Hosting

- **Site:** GitHub Pages serving `index.html`, mapped to **clipandcue.com** via the
  `CNAME` file + DNS (apex A records → GitHub Pages IPs, `www` CNAME), with
  *Enforce HTTPS* on (free Let's Encrypt cert).
- **Downloads:** GitHub Releases (the notarized `.dmg`).
- **Analytics:** cookieless page-view + download tracking on the site.

## License

© 2026 Michael Moore. clipandcue is licensed under
[Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](LICENSE).

You're free to use, modify, and share it **for non-commercial purposes**, with
attribution. **Commercial use is not permitted.**
