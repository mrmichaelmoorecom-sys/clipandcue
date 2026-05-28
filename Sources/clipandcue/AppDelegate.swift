import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipStore()
    private let settings = AppSettings.shared
    private var monitor: ClipboardMonitor!
    private var statusController: StatusItemController!
    private var quickPaste: QuickPasteController!
    private var hotkey: GlobalHotkey!
    private var prefsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()

        let sc = StatusItemController(store: store)
        sc.onPick = { [weak self] idx in self?.paste(index: idx) }
        sc.onPreferences = { [weak self] in self?.openPreferences() }
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
        m.start()
        monitor = m
    }

    private func paste(index: Int) {
        guard let item = store.item(at: index) else { return }
        Paster.shared.deliver(item, autoPaste: settings.autoPaste)
    }

    private func openPreferences() {
        if prefsWindow == nil {
            let host = NSHostingController(rootView: PreferencesView(store: store))
            let win = NSWindow(contentViewController: host)
            win.title = "clipandcue Preferences"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            prefsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.center()
        prefsWindow?.makeKeyAndOrderFront(nil)
    }
}
