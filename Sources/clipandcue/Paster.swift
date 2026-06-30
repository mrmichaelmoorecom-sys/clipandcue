import AppKit

/// Restores an item to the pasteboard and (optionally) pastes it into the
/// app that was frontmost before our UI appeared.
final class Paster {
    static let shared = Paster()

    /// Fired immediately before any pasteboard write Paster does. AppDelegate
    /// hooks this to `ClipboardMonitor.suppressNextChange()` so our rewrites
    /// don't reorder/recapture the clip we just delivered. Stacks correctly
    /// across the N writes a multi-file sequential paste performs.
    var onWillWritePasteboard: (() -> Void)?

    private var targetApp: NSRunningApplication?

    /// Capture the foreground app before we show the menu/HUD, so we can paste back into it.
    func rememberFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        }
    }

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Throttle so we don't pop the alert every time the user tries to paste
    /// while permission is still missing. Reset on grant (next paste will
    /// succeed and clear this implicitly) so it re-arms if perms are revoked.
    private var accessibilityAlertShown = false

    /// User-facing fallback when the system prompt didn't appear or was
    /// dismissed. The TCC process-side cache means newly-granted permission
    /// usually doesn't take effect until relaunch, so we make the relaunch
    /// trivial with a "Quit clipandcue" button.
    func explainAccessibilityNeeded() {
        guard !accessibilityAlertShown else { return }
        accessibilityAlertShown = true
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "clipandcue needs Accessibility to paste automatically"
            alert.informativeText = """
                Auto-paste uses the Accessibility permission to send ⌘V to the app you were just in. Without it, items only land on the clipboard and you have to paste yourself.

                1. Click "Open Settings" below.
                2. Find clipandcue in the Accessibility list and turn it on.
                3. Quit and relaunch clipandcue — macOS only picks up the permission for already-running apps after a restart.
                """
            alert.addButton(withTitle: "Open Settings…")
            alert.addButton(withTitle: "Quit clipandcue")
            alert.addButton(withTitle: "Not Now")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                self.requestAccessibility()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            case .alertSecondButtonReturn:
                NSApp.terminate(nil)
            default:
                break
            }
        }
    }

    /// Place `item` on the clipboard; if `autoPaste` and Accessibility is granted,
    /// reactivate the previous app and synthesize ⌘V.
    func deliver(_ item: ClipItem, autoPaste: Bool) {
        // User-assembled stack: paste every child sequentially. Each child
        // is delivered via the same writeToPasteboard path (snapshot when
        // present, per-kind otherwise) — so a group can mix text, images,
        // files, design-app copies and they all paste back at full
        // fidelity in order.
        if item.kind == .group, let kids = item.children, !kids.isEmpty {
            deliverGroup(kids, autoPaste: autoPaste)
            return
        }

        writeToPasteboard(item)
        guard autoPaste else { return }
        guard hasAccessibility else {
            requestAccessibility()
            explainAccessibilityNeeded()
            return
        }
        targetApp?.activate(options: [.activateIgnoringOtherApps])

        // Multi-file clip: paste each file in its own ⌘V cycle. Photoshop,
        // Illustrator, and similar apps only consume the first pasteboard
        // item per paste, so a single ⌘V with N file URLs drops files 2..N.
        // Sequential pastes (each with one URL on the pasteboard) reliably
        // give all of them — including in apps like Keynote that handle
        // multi-paste natively.
        if item.kind == .files, let paths = item.filePaths, paths.count > 1 {
            sendMultiFilePaste(paths)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.sendCommandV()
            }
        }
    }

    private func deliverGroup(_ children: [ClipItem], autoPaste: Bool) {
        // Put the first child on the pasteboard right away so the user
        // gets something usable from a manual ⌘V even without Accessibility.
        if let first = children.first { writeToPasteboard(first) }
        guard autoPaste else { return }
        guard hasAccessibility else {
            requestAccessibility()
            explainAccessibilityNeeded()
            return
        }
        targetApp?.activate(options: [.activateIgnoringOtherApps])

        let leadIn: TimeInterval = 0.18
        let step: TimeInterval = 0.50
        for (i, child) in children.enumerated() {
            let delay = leadIn + Double(i) * step
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.writeToPasteboard(child)
                self?.sendCommandV()
            }
        }
    }

    private func sendMultiFilePaste(_ paths: [String]) {
        let leadIn: TimeInterval = 0.18
        // Illustrator finishes a paste noticeably slower than Photoshop /
        // Keynote — half a second between cycles keeps the sequence reliable
        // there without feeling laggy in faster apps.
        let step: TimeInterval = 0.50
        let pb = NSPasteboard.general
        for (i, path) in paths.enumerated() {
            let delay = leadIn + Double(i) * step
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.onWillWritePasteboard?()
                pb.clearContents()
                Self.writeFile(at: path, to: pb)
                self?.sendCommandV()
            }
        }
    }

    /// Write one file to the pasteboard with the richest representations the
    /// content allows: always the file URL (so Finder, Mail, web inputs etc.
    /// see it as a file), plus a raster TIFF for image files and the raw PDF
    /// bytes for `.pdf` / `.ai` / `.eps` so apps that ignore file-URL pastes
    /// (notably Illustrator) still receive the content.
    private static func writeFile(at path: String, to pb: NSPasteboard) {
        let url = URL(fileURLWithPath: path)
        pb.writeObjects([url as NSURL])
        let ext = (path as NSString).pathExtension.lowercased()
        if ["pdf", "ai", "eps"].contains(ext),
           let data = try? Data(contentsOf: url) {
            pb.setData(data, forType: NSPasteboard.PasteboardType("com.adobe.pdf"))
        } else if let image = NSImage(contentsOfFile: path),
                  let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    private func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        onWillWritePasteboard?()
        pb.clearContents()

        // High-fidelity path: replay every pasteboard type captured at copy.
        // Apps that own private types (Illustrator's AICB, Keynote's TSP*,
        // Word's OOXML, Sketch / Affinity / Office etc.) see the exact same
        // pasteboard the user had at copy time, so paste-back is editable
        // instead of a flattened PDF.
        if let snap = item.pasteboardSnapshot, !snap.isEmpty, item.kind != .files {
            // For richText clips honor the user's "paste as plain text" pref
            // by stripping format reps before writing.
            let toWrite: [String: Data]
            if item.kind == .richText && AppSettings.shared.pasteAsPlainText {
                toWrite = snap.filter { (k, _) in
                    k == "public.utf8-plain-text" || k == "public.text"
                }
            } else {
                toWrite = snap
            }
            for (type, data) in toWrite {
                pb.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return
        }

        // Fallback path: legacy clips (pre-v0.2.6), CloudKit-pulled clips,
        // and .files clips. Same per-kind writes as before.
        switch item.kind {
        case .text:
            if let t = item.text { pb.setString(t, forType: .string) }
        case .richText:
            if !AppSettings.shared.pasteAsPlainText, let rtf = item.rtfData {
                pb.setData(rtf, forType: .rtf)
            }
            if let t = item.text { pb.setString(t, forType: .string) }
        case .image:
            if let data = item.imageData {
                let ut = item.imageUTType ?? ""
                let type: NSPasteboard.PasteboardType
                if ut.contains("pdf") {
                    type = NSPasteboard.PasteboardType("com.adobe.pdf")
                } else if ut.contains("png") {
                    type = .png
                } else {
                    type = .tiff
                }
                pb.setData(data, forType: type)
                // Add a TIFF raster fallback for apps that don't accept the
                // primary type (PDF in particular).
                if type != .tiff, let img = NSImage(data: data),
                   let tiff = img.tiffRepresentation {
                    pb.setData(tiff, forType: .tiff)
                }
            }
        case .files:
            if let paths = item.filePaths {
                if paths.count == 1, let path = paths.first {
                    Self.writeFile(at: path, to: pb)
                } else {
                    let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                    pb.writeObjects(urls)
                }
            }
        case .group:
            // Manual fallback: put the first child on the pasteboard.
            // (Real group paste is handled in `deliver` via sequential ⌘V
            // through this same per-kind path for each child.)
            if let first = item.children?.first {
                writeToPasteboard(first)
            }
        }
    }

    private func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
