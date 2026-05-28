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
                                    onPick: { [weak self] idx in self?.select(idx) })
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
        NSApp.activate(ignoringOtherApps: true)
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
