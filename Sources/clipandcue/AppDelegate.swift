import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipStore()
    private let settings = AppSettings.shared
    private var monitor: ClipboardMonitor!
    private let cloud = MacCloudKitSync()
    private var statusController: StatusItemController!
    private var quickPaste: QuickPasteController!
    private var hotkey: GlobalHotkey!
    private var prefsWindow: NSWindow?
    private var howToWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()

        let sc = StatusItemController(store: store)
        sc.onPick = { [weak self] idx in self?.paste(index: idx) }
        sc.onPreferences = { [weak self] in self?.openPreferences() }
        sc.onHowTo = { [weak self] in self?.openHowTo() }
        sc.onExport = { [weak self] in
            guard let self else { return }
            Exporter.exportToTextEdit(self.store.items)
        }
        statusController = sc

        let qp = QuickPasteController(store: store)
        qp.onPick = { [weak self] idx in self?.paste(index: idx) }
        quickPaste = qp

        let hk = GlobalHotkey()
        hk.onTrigger = { [weak self] in self?.quickPaste.toggle() }
        hk.register()
        hotkey = hk

        let m = ClipboardMonitor(store: store)
        m.onOversized = { [weak self] bytes, label in
            self?.statusController.flashWarning()
            Notifier.shared.notifyOversized(bytes: bytes, kindLabel: label)
        }
        // Push each freshly captured clip (text or image) up to CloudKit so it
        // reaches the iPhone. MacCloudKitSync filters out unsyncable kinds.
        m.onCaptured = { [weak self] item in
            self?.cloud.push(item)
        }
        m.start()
        monitor = m

        // Pull any clips the iPhone (or another device) saved while we were away.
        Task { await cloud.pull(into: store) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if settings.clearOnQuit {
            store.purgePersistedNow()
        }
    }

    private func paste(index: Int) {
        guard let item = store.item(at: index) else { return }
        // Don't let our own re-write of the pasteboard reorder the item.
        monitor.suppressNextChange()
        Paster.shared.deliver(item, autoPaste: settings.autoPaste)
    }

    private func openPreferences() {
        if prefsWindow == nil {
            let root = PreferencesView(store: store, onHowTo: { [weak self] in self?.openHowTo() })
            let host = NSHostingController(rootView: root)
            host.sizingOptions = [.preferredContentSize]
            let win = NSWindow(contentViewController: host)
            win.title = "clip and cue Preferences"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            prefsWindow = win
        }
        show(prefsWindow)
    }

    private func openHowTo() {
        if howToWindow == nil {
            let host = NSHostingController(rootView: HowToView())
            host.sizingOptions = [.preferredContentSize]
            let win = NSWindow(contentViewController: host)
            win.title = "How to use clip and cue"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            howToWindow = win
        }
        show(howToWindow)
    }

    private func show(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
