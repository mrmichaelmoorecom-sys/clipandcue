# clipandcue v0.2.3 — QC report (build + static code review)

**Method note.** This QC was run as a **build + source review**, not the
interactive walkthrough in [`QC-v0.2.3.md`](QC-v0.2.3.md). The reason: the entire
interactive surface — the menu-bar dropdown (`NSPopover`) and the ⌘⌥V HUD
(borderless `.nonactivatingPanel`) — is exactly the overlay-window class that
macOS **excludes from the agent's screenshots**, so a computer-use agent can't
observe §2–§8. Drag-and-drop across apps, Accessibility-gated auto-paste, and the
Adobe targets in §6 are likewise outside what the agent can drive here. So instead
of clicking blind, I read the v0.2.3 diff and traced the new logic. Findings below
are **code-level** — high confidence on logic, but the runtime/visual items still
need a human at the machine (checklist in §B).

- **Build:** `scripts/build_app.sh debug` → **success, no warnings.**
- **Version:** `Info.plist` CFBundleShortVersionString = **0.2.3**. (Built from
  source; the notarized-DMG / Gatekeeper check in plan §1 was not exercised.)
- **Scope reviewed:** the 11 files in commit `482eebe` (v0.2.3).

---

## A. Findings

### 🔴 BUG-1 (major, high confidence) — multi-file paste leaks the suppression counter, silently dropping the *next* real copy
**Where:** `ClipboardMonitor.poll()` (`ClipboardMonitor.swift:50-69`) vs the writes
in `Paster.sendMultiFilePaste` / `Paster.deliver` (`Paster.swift:36, 50-75`).

**Mechanism.** The monitor polls the pasteboard every **0.4 s** and, per tick,
processes *one* change and decrements `skipChangeCount` by **exactly 1**
(`ClipboardMonitor.swift:55-58`) — regardless of how many pasteboard writes
actually happened since the last tick. A multi-file auto-paste performs **N+1**
pasteboard writes in a burst:
1. `deliver()` calls `writeToPasteboard(item)` first (`Paster.swift:36`) — writes
   all URLs (1 write, 1 `suppressNextChange`), then
2. `sendMultiFilePaste` writes each file in its own cycle at `0.18 s`, `0.68 s`,
   `1.18 s …` (`Paster.swift:60-74`) — N writes, N `suppressNextChange`.

The initial write (~t=0) and the first cycle write (t=0.18) both fall inside the
**same 0.4 s poll window**, so `changeCount` jumps by 2 but the poll decrements
`skipChangeCount` by only 1. The leftover **+1 never clears** — so the **next
genuine copy** the user makes is matched against the stale suppression and
**silently dropped from history** (and, because `onCaptured` never fires, not
pushed to CloudKit either). Larger N or any main-thread stall (see BUG-2) can leak
more than 1.

**Why §7 may not catch it:** §7 only checks that the paste *doesn't add* rows —
over-suppression actually *passes* that check. The damage shows on the *following*
copy, which §7 doesn't ask the operator to make.

**Manual repro (≈30 s):** copy 3 files from Finder → click the parent row to
auto-paste them somewhere → then copy a brand-new text snippet → open the dropdown.
**Expected:** the new snippet is at the top. **Likely actual:** it's missing (the
first copy after the multi-file paste was swallowed); a second copy reappears.

**Fix direction:** decrement by the delta, e.g.
`let delta = current - lastChangeCount; let drop = min(skipChangeCount, delta); skipChangeCount -= drop`
and only treat the change as user-originated when `delta > drop`. Also consider
**not** calling `writeToPasteboard` in `deliver()` for the multi-file auto-paste
branch (it's immediately overwritten by cycle 0 — see MINOR-1), which removes the
t=0/t=0.18 coalescing that triggers the leak.

### 🟠 BUG-2 (minor→major, perf/reliability) — synchronous file decode on the main thread inside the paste loop
**Where:** `Paster.writeFile` (`Paster.swift:82-93`), called from each paste cycle
on the main queue (`Paster.swift:68-71`).

Each cycle does `Data(contentsOf:)` for `.pdf/.ai/.eps` (`:87`) or
`NSImage(contentsOfFile:) + tiffRepresentation` for images (`:89-91`) **on the main
thread**. For large files this can hitch/beachball the UI mid-paste and, worse,
delay the *next* scheduled cycle or the 0.4 s poll — which makes the BUG-1
coalescing more likely and risks a destination "running while the app wasn't
ready" (the dropped-file case the plan flags in §6). Decode/read off-main and hand
the bytes back to the main queue just to set them on the pasteboard.

### 🟡 MINOR-1 — redundant initial pasteboard write for multi-file auto-paste
`deliver()` always runs `writeToPasteboard(item)` (`Paster.swift:36`); for the
multi-file branch that full multi-URL write is discarded ~0.18 s later by cycle 0.
Harmless on its own, but it's wasted work and it's the write that coalesces into
BUG-1. (When auto-paste is *off*, this write is correct and needed — so guard it on
the auto-paste+multi-file branch only.)

### 🟡 MINOR-2 — expand/collapse and chevron rotation are not animated (§8)
`toggleExpand` mutates `expandedItems` with no `withAnimation`
(`MenuListView.swift:146-152`, `QuickPasteHUDView.swift:118-124`), and the chevron's
`.rotationEffect` (`ClipRowView.swift:82`) has no animation context. So the 90°
rotation and the sub-row reveal **snap** rather than animate. Not janky, but §8's
"smooth" expectation isn't met. Wrap the toggle in `withAnimation(.easeInOut)`.

### 🟡 MINOR-3 — sub-row previews re-decode on every expansion
`FileSubRowView.loadPreview` re-reads + re-decodes the file each time the row
appears (`FileSubRowView.swift:59-74`); collapse/expand repeats the work. The
parent-row thumbnail is also generated separately at capture time
(`ClipboardMonitor.fileThumbnail`). Functional, but a small cache keyed by path
would avoid redundant decodes.

### ⚪ COSMETIC — image row size label includes the thumbnail bytes
`displaySecondary` "PNG · NN KB" uses `byteSize`, which sums `imageData` **plus**
`thumbnailData` (`ClipItem.swift:62-69, 113-114`), so the reported size is a few KB
high vs the actual PNG. Negligible.

---

## What looks correct in the code (would expect PASS)

- **§2 smoke:** capture of text/rich-text/image/files, newest-first, dedup
  (`ClipItem.sameContent`), pin, and search (incl. matching file names,
  `MenuListView.swift:34-37`) all read correctly. Image label "Image · W×H" /
  "PNG · NN KB" matches §2.7 exactly (`ClipItem.swift:94, 113-114`).
- **§3 drag:** per-kind providers are right — text→NSString, image→NSImage,
  file→file-URL (`ClipItem+Drag.swift`); sub-rows carry their own file URL
  (`FileSubRowView.swift:54`). Multi-file parent drag = first file only, which is
  **by design and matches §3.4**.
- **§4 previews:** image/PDF thumbnail via `NSImage(contentsOfFile:)`, 50 MB cap,
  generic-icon fallback for non-image / oversized — all correct
  (`ClipboardMonitor.fileThumbnail`, `FileSubRowView.loadPreview`).
- **§5 expansion:** chevron shown only for multi-file (`MenuListView.swift:115`),
  expansion state keyed by **item id** (survives list reordering), per-file paste
  wired to `pasteFile` building a single-path clip (`AppDelegate.swift:113-119`),
  sub-row tap/drag correct, HUD uses the larger 36 px variant with a tinted
  container (`QuickPasteHUDView.swift:50, 56-59`).
- **§6 multi-file paste:** the approach is sound — one ⌘V per file with a 0.5 s gap,
  writing file-URL + **TIFF** for images and **com.adobe.pdf** for pdf/ai/eps so
  Illustrator/Photoshop receive content (`Paster.swift:59-93`). Order preserved.
  The frontmost app is captured on open (`StatusItemController.swift:122`,
  `QuickPasteController.swift:33`) and re-activated before the cycle
  (`Paster.swift:42`). (Caveat: not re-activated *per cycle* — see §B.)
- **§7 suppression:** the counter *concept* is right and stacks across N writes;
  it's only the **poll-side decrement** that's wrong (BUG-1).
- **Menu-bar icon (§8):** template paperclip, re-rendered crisp at device pixels
  (`StatusItemController.swift:43-70`) — no expected regression.

---

## B. "Needs a human at the machine" checklist

Agent-blocked (NSPopover / HUD / cross-app / Adobe / notarization). Please verify:

1. **BUG-1 repro** (the important one): multi-file auto-paste → then copy something
   new → confirm it appears at the top of history. If it's missing, BUG-1 is real.
2. **§1 install:** notarized DMG opens with no Gatekeeper prompt; menu-bar icon,
   no Dock icon; Preferences shows 0.2.3 (build 14); Accessibility prompt flow.
3. **§3 / §3.5 drag-and-drop** from both dropdown and HUD (press-hold drags,
   quick-tap still pastes) into TextEdit / Preview / Finder.
4. **§5.8 HUD on expand:** confirm the panel **stays put** and the inner area
   **scrolls** (panel size is fixed at show-time, so it should — but eyeball it,
   especially when only 1–2 items exist and you expand a 5-file row).
5. **§6 per-app paste** — TextEdit / Notes / Keynote / Photoshop / Illustrator.
   Mark Illustrator **N/A** if not installed. Watch for any dropped file when a
   cycle runs before the app is ready (made more likely by BUG-2 with large files).
6. **§6 timing** — re-activation is once-up-front, not per cycle; if focus is stolen
   mid-sequence, later ⌘Vs miss. Confirm the ~1.5 s/3-file batch lands fully.
7. **§8 visuals** — the snap vs animate point (MINOR-2), sub-row indentation,
   hover-highlight bleed, drag-ghost, icon crispness.

---

## C. Summary

| Section | Code-review verdict |
|---|---|
| §2 Smoke | Looks correct |
| §3 Drag-and-drop | Correct (multi-file = first-file by design) |
| §4 File previews | Correct |
| §5 Multi-file expansion | Correct |
| §6 Multi-file paste | Sound approach; **reliability risk under BUG-2** |
| §7 Suppression loop | **BUG-1 — counter leaks, drops the next copy** |
| §8 Visual polish | MINOR-2 (no animation) + eyeball items |

**Priority:** BUG-1 (fix the poll decrement) → BUG-2 (decode off-main) → MINOR-1
(drop the redundant write) → MINOR-2 (animate expand) → MINOR-3 (cache previews).

_No code changes were made during QC. Build verified; interactive sections need
the manual passes in §B._
