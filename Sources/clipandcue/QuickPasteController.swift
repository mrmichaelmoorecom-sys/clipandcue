import AppKit
import SwiftUI
import Carbon.HIToolbox

final class QuickPastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows/hides the floating Quick Paste HUD and handles its key input.
final class QuickPasteController: NSObject, NSWindowDelegate {
    var onPick: ((Int) -> Void)?
    /// Paste a single file from an expanded multi-file clip.
    /// `(itemIndex, fileIndex)` resolves against the store.
    var onPickFile: ((Int, Int) -> Void)?
    /// Paste a single child from an expanded group clip.
    /// `(groupIndex, childIndex)` resolves against the store.
    var onPickGroupChild: ((Int, Int) -> Void)?

    private let store: ClipStore
    private let model = QuickPasteModel()
    private var panel: QuickPastePanel?
    private var keyMonitor: Any?

    init(store: ClipStore) {
        self.store = store
        super.init()
    }

    var isVisible: Bool { panel != nil }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard panel == nil else { return }
        Paster.shared.rememberFrontmostApp()
        model.selection = 0

        let hud = QuickPasteHUDView(store: store, model: model,
                                    onPick: { [weak self] idx in self?.select(idx) },
                                    onPickFile: { [weak self] idx, fi in
                                        self?.hide()
                                        self?.onPickFile?(idx, fi)
                                    },
                                    onPickGroupChild: { [weak self] idx, ci in
                                        self?.hide()
                                        self?.onPickGroupChild?(idx, ci)
                                    })
        let host = NSHostingView(rootView: hud)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let panel = QuickPastePanel(contentRect: NSRect(origin: .zero, size: size),
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = host
        panel.delegate = self
        panel.setContentSize(size)
        position(panel)

        self.panel = panel
        // Don't `NSApp.activate(ignoringOtherApps: true)` here — that would
        // bring clipandcue to the foreground and steal the cursor from
        // whatever text field the user was in (which is the very thing
        // we're about to paste into). `.nonactivatingPanel` in the style
        // mask plus `makeKeyAndOrderFront` give the panel keyboard focus
        // for 1-9 / ⏎ / esc *without* activating our app, so the user's
        // previous text-field focus stays intact and the post-pick
        // `targetApp?.activate(...)` puts the cursor right back where it
        // started.
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        guard panel != nil else { return }
        removeKeyMonitor()
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func select(_ idx: Int) {
        guard store.items.indices.contains(idx) else { return }
        hide()
        onPick?(idx)
    }

    private func position(_ panel: NSPanel) {
        guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame else {
            panel.center(); return
        }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2 + frame.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let count = store.items.count
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            select(model.selection); return true
        case kVK_DownArrow:
            if count > 0 { model.selection = min(count - 1, model.selection + 1) }
            return true
        case kVK_UpArrow:
            if count > 0 { model.selection = max(0, model.selection - 1) }
            return true
        default:
            if let s = event.charactersIgnoringModifiers, let n = Int(s), n >= 1, n <= 9 {
                select(n - 1); return true
            }
            return false
        }
    }
}
