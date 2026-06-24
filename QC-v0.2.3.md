# QC plan — clipandcue v0.2.3

**For the QC operator (Claude on another Mac):** work through the cases below in order, marking each PASS / FAIL / N/A with notes. At the end, return a single report following the template at the bottom. Don't fix bugs — just observe and record.

---

## 1. Install

1. Download the notarized DMG:
   https://github.com/mrmichaelmoorecom-sys/clipandcue/releases/download/v0.2.3/clipandcue.dmg
2. Open the DMG, drag **clipandcue** to **/Applications**, eject.
3. Launch `/Applications/clipandcue.app`. Confirm:
   - Menu bar shows a white paperclip-style icon (top-right).
   - No Dock icon appears.
   - No Gatekeeper warning fires (notarization is stapled).
4. First time auto-paste is triggered the system will prompt for **Accessibility** — grant it in System Settings → Privacy & Security → Accessibility, then quit & relaunch clipandcue.
5. About box / Preferences should report version **0.2.3** (build 14). Confirm via menu bar dropdown → Preferences.

---

## 2. Smoke (regression — these existed before v0.2.3)

| # | Action | Expected |
|---|---|---|
| 2.1 | Copy three different text snippets in succession | All three appear in the menu bar dropdown, newest at top |
| 2.2 | Click any text row | Paste fires into the previously focused app |
| 2.3 | Hit ⌘⌥V | HUD appears centered-ish, dismisses on Esc |
| 2.4 | In HUD, press `1` | Top item pastes |
| 2.5 | In dropdown, click a number badge | Item pins (accent fill + pin glyph), moves to top |
| 2.6 | Click the magnifying-glass chip in footer | Search field appears, filters as you type |
| 2.7 | Copy a screenshot (⌘⇧4) | New row with a thumbnail, label `Image · WxH`, `PNG · NN KB` |

---

## 3. Drag-and-drop (NEW)

For each row type, **press-and-hold then drag** the row from the menu bar dropdown out to another app. Repeat the same set from the ⌘⌥V HUD.

| # | Source row | Drop target | Expected |
|---|---|---|---|
| 3.1 | Text clip | TextEdit doc | Text inserts at drop point |
| 3.2 | Image clip (from ⌘⇧4 screenshot) | Preview / Photoshop / Mail compose | Image inserts |
| 3.3 | File clip (single, copied from Finder) | Finder window | File copies into that folder |
| 3.4 | File clip (multi-file) — drag the *parent* row | Finder window | First file copies (multi-file drag is single-file by design) |
| 3.5 | Repeat 3.1–3.3 from the **HUD** | same as above | Same behavior |

The drag should kick in after a short press; a quick tap should still paste (existing behavior).

---

## 4. File previews (NEW)

In Finder, copy single files of each type and check the menu bar dropdown row:

| # | Copy this from Finder | Expected preview |
|---|---|---|
| 4.1 | A `.jpg` / `.png` / `.heic` image | Actual content thumbnail (not generic photo icon) |
| 4.2 | A `.pdf` | First-page preview |
| 4.3 | A `.txt` / `.zip` / non-image file | Generic file icon (this is correct — no preview expected) |
| 4.4 | An image file > 50 MB | Generic file icon (by-design cap) |

Items captured *before* the upgrade won't have previews — that's expected. Trigger fresh captures for this section.

---

## 5. Multi-file expansion (NEW)

1. In Finder, select **3+ files** (mix images and a PDF if possible), ⌘C.
2. Open the menu bar dropdown.

| # | Action | Expected |
|---|---|---|
| 5.1 | Row appears | Shows first filename + `+N more`, with a chevron on the right |
| 5.2 | Click the chevron | Row expands; chevron rotates 90°; sub-rows appear indented below |
| 5.3 | Each sub-row | Shows file name + thumbnail (real preview for images/PDFs, system icon for others) loaded async — fallback icon may show briefly before the thumbnail swaps in |
| 5.4 | Hover a sub-row | Accent-tinted highlight |
| 5.5 | Click a sub-row | Just that one file pastes; popover dismisses |
| 5.6 | Drag a sub-row to Finder | That one file copies |
| 5.7 | Click chevron again | Collapses cleanly |
| 5.8 | Repeat 5.1–5.7 from the **HUD** | Sub-rows are larger (~36 px); HUD stays put, inner area scrolls if needed |

---

## 6. Multi-file paste (NEW — the load-bearing fix)

Copy a multi-file clip (3+ files, ideally images) from Finder, then click the **parent row** in the dropdown. Auto-paste must be enabled (default).

| # | Destination app | Expected |
|---|---|---|
| 6.1 | TextEdit | All file paths/URLs paste in order (one per line is fine) |
| 6.2 | Notes | Each file becomes a separate inline attachment |
| 6.3 | Keynote | Each image inserts as a separate element on the active slide |
| 6.4 | Photoshop | Each image opens as its own new document or layer (one per ⌘V cycle) |
| 6.5 | Illustrator | Each image / PDF places as a separate object (this is the bug the release fixes — pre-0.2.3, only one would land) |

Timing: each paste cycle is gapped by **~0.5 s**. The whole batch for N=3 files should complete in ~1.5 s. Note if any destination drops a file (cycle ran while app wasn't ready).

`.svg` files specifically have no standard pasteboard type — those will still need File → Place in Illustrator. Don't flag that as a regression.

---

## 7. Suppression / capture loop

This guards against a regression where pasting a multi-file clip re-captures itself.

| # | Action | Expected |
|---|---|---|
| 7.1 | Paste a 3-file clip from the dropdown (case 6.x) | The clip's position in history doesn't shuffle; no new entries appear at the top representing your own paste activity |
| 7.2 | Repeat with a 5-file clip | Same — history is stable |

---

## 8. Visual polish to eye-ball

- Chevron rotation when expanding is smooth (no jank).
- Sub-row indentation is consistent with the parent row's text column.
- Hover highlights on sub-rows don't bleed past the row edges.
- The HUD's sub-row container has a subtle tint differentiating it from parent rows.
- Drag-ghost looks like the row content (default SwiftUI ghost is fine).
- Menu bar icon is still a clean white paperclip (no regression in icon crispness).

---

## Report template

Return a single comment with this shape:

```
clipandcue v0.2.3 QC — <machine name>, <macOS version>, <date>

Smoke (§2): PASS / FAIL
Drag-and-drop (§3): PASS / FAIL — notes:
File previews (§4): PASS / FAIL — notes:
Multi-file expansion (§5): PASS / FAIL — notes:
Multi-file paste (§6): PASS / FAIL — per-app notes:
  - TextEdit:
  - Notes:
  - Keynote:
  - Photoshop:
  - Illustrator:
Suppression loop (§7): PASS / FAIL
Visual polish (§8): notes

Issues found:
1. <one-line title>
   - Repro: <steps>
   - Expected: <…>
   - Actual: <…>
   - Severity: blocker / major / minor / cosmetic
   - Screenshot / log path (if any):
```

If the host machine doesn't have a given app from §6 (Illustrator is often the missing one), mark that row **N/A** rather than skipping silently. The rest of the plan does not require Adobe apps.
