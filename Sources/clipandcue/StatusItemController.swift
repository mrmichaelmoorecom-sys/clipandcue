import AppKit
import SwiftUI

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: ClipStore
    private var warningTimer: Timer?

    var onPick: ((Int) -> Void)?
    var onPreferences: (() -> Void)?

    init(store: ClipStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configurePopover()
    }

    // MARK: Icon

    private func normalIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        let img = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "clipandcue")
        img?.isTemplate = true
        return img
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = normalIcon()
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let root = MenuListView(
            store: store,
            onPick: { [weak self] idx in self?.handlePick(idx) },
            onClear: { [weak self] in self?.store.clear() },
            onPreferences: { [weak self] in
                self?.closePopover()
                self?.onPreferences?()
            },
            onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
            return
        }
        Paster.shared.rememberFrontmostApp()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() { popover.performClose(nil) }

    private func handlePick(_ index: Int) {
        closePopover()
        onPick?(index)
    }

    // MARK: Not-saved warning

    func flashWarning() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
        let warn = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                           accessibilityDescription: "Copy not saved")?
            .withSymbolConfiguration(config)
        warn?.isTemplate = false
        button.image = warn
        warningTimer?.invalidate()
        warningTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.statusItem.button?.image = self?.normalIcon()
        }
    }
}
