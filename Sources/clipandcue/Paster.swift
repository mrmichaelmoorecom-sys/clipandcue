import AppKit

/// Restores an item to the pasteboard and (optionally) pastes it into the
/// app that was frontmost before our UI appeared.
final class Paster {
    static let shared = Paster()

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

    /// Place `item` on the clipboard; if `autoPaste` and Accessibility is granted,
    /// reactivate the previous app and synthesize ⌘V.
    func deliver(_ item: ClipItem, autoPaste: Bool) {
        writeToPasteboard(item)
        guard autoPaste else { return }
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        targetApp?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.sendCommandV()
        }
    }

    private func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            if let t = item.text { pb.setString(t, forType: .string) }
        case .richText:
            if let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            if let t = item.text { pb.setString(t, forType: .string) }
        case .image:
            if let data = item.imageData {
                let type: NSPasteboard.PasteboardType =
                    (item.imageUTType?.contains("png") == true) ? .png : .tiff
                pb.setData(data, forType: type)
                if type != .tiff, let img = NSImage(data: data),
                   let tiff = img.tiffRepresentation {
                    pb.setData(tiff, forType: .tiff)
                }
            }
        case .files:
            if let paths = item.filePaths {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                pb.writeObjects(urls)
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
