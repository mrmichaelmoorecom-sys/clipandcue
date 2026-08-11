import AppKit
import Combine
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = ClipStore()
    private let settings = AppSettings.shared
    private var monitor: ClipboardMonitor!
    private let cloud = MacCloudKitSync()
    private var statusController: StatusItemController!
    private var quickPaste: QuickPasteController!
    private var hotkey: GlobalHotkey!
    private var prefsWindow: NSWindow?
    private var howToWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Routes notification button taps (e.g. the "Open Preferences"
        // action on the oversized-copy alert) back into the app. The
        // permission PROMPT is deferred until the first notification is
        // actually needed (Notifier.requestAuthorizationIfNeeded) so a fresh
        // install shows no dialogs at launch.
        UNUserNotificationCenter.current().delegate = self
        Notifier.shared.registerCategories()

        let sc = StatusItemController(store: store)
        sc.onPick = { [weak self] idx in self?.paste(index: idx) }
        sc.onPickFile = { [weak self] idx, fileIdx in self?.pasteFile(itemIndex: idx, fileIndex: fileIdx) }
        sc.onPickGroupChild = { [weak self] idx, childIdx in self?.pasteGroupChild(groupIndex: idx, childIndex: childIdx) }
        sc.onPreferences = { [weak self] in self?.openPreferences() }
        sc.onHowTo = { [weak self] in self?.openHowTo() }
        sc.onExport = { [weak self] in
            guard let self else { return }
            Exporter.exportToTextEdit(self.store.items)
        }
        statusController = sc

        let qp = QuickPasteController(store: store)
        qp.onPick = { [weak self] idx in self?.paste(index: idx) }
        qp.onPickFile = { [weak self] idx, fileIdx in self?.pasteFile(itemIndex: idx, fileIndex: fileIdx) }
        qp.onPickGroupChild = { [weak self] idx, childIdx in self?.pasteGroupChild(groupIndex: idx, childIndex: childIdx) }
        quickPaste = qp

        let hk = GlobalHotkey()
        hk.onTrigger = { [weak self] in self?.quickPaste.toggle() }
        hk.register(keyCode: UInt32(settings.hotkeyKeyCode),
                    modifiers: UInt32(settings.hotkeyModifiers))
        hotkey = hk

        // Re-register whenever the user picks a new shortcut in Preferences.
        // dropFirst skips the immediate emission on subscribe — we already
        // registered with the loaded values above.
        settings.$hotkeyKeyCode
            .combineLatest(settings.$hotkeyModifiers)
            .dropFirst()
            .sink { [weak self] keyCode, mods in
                self?.hotkey.register(keyCode: UInt32(keyCode),
                                      modifiers: UInt32(mods))
            }
            .store(in: &cancellables)

        // Suppress one monitor tick per pasteboard write Paster performs. For
        // single pastes that's one; for multi-file sequential pastes that's N.
        // The counter inside ClipboardMonitor stacks these correctly.
        Paster.shared.onWillWritePasteboard = { [weak self] in
            self?.monitor?.suppressNextChange()
        }

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

        // When the user clears history, also delete the clips from CloudKit so
        // nothing sensitive lingers in the cloud or re-syncs back.
        store.onClear = { [weak self] in
            Task { await self?.cloud.deleteAll() }
        }

        // Pull any clips the iPhone (or another device) saved while we were away,
        // and register for live updates: a silent CloudKit push wakes us to pull
        // when a clip changes on another device.
        NSApplication.shared.registerForRemoteNotifications()
        Task {
            await cloud.ensureSubscription()
            await cloud.pull(into: store)
        }
    }

    /// Silent CloudKit push → fetch the latest clips (live cross-device sync).
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { await cloud.pull(into: store) }
    }

    /// One-tap "Open Preferences" action on the oversized-copy notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Notifier.openPreferencesAction {
            openPreferences()
        }
        completionHandler()
    }

    /// Fallback for when a push is missed: refresh whenever the app is focused.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await cloud.pull(into: store) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if settings.clearOnQuit {
            // Detach the normal onClear handler so we don't kick off a
            // background `Task { await deleteAll() }` that gets killed when
            // the process exits a few ms later. Instead wait synchronously
            // (bounded) on the cloud delete so a cleared password really is
            // gone before quit returns.
            store.onClear = nil
            store.purgePersistedNow()
            cloud.deleteAllAndWait(timeout: 5)
        }
    }

    private func paste(index: Int) {
        guard let item = store.item(at: index) else { return }
        Paster.shared.deliver(item, autoPaste: settings.autoPaste)
    }

    /// Paste a single file out of a multi-file clip — used when the user
    /// expands a files row and clicks one of the sub-rows.
    private func pasteFile(itemIndex: Int, fileIndex: Int) {
        guard let item = store.item(at: itemIndex),
              let paths = item.filePaths,
              paths.indices.contains(fileIndex) else { return }
        let single = ClipItem(kind: .files, filePaths: [paths[fileIndex]])
        Paster.shared.deliver(single, autoPaste: settings.autoPaste)
    }

    /// Paste a single child out of an expanded group, via its index pair.
    private func pasteGroupChild(groupIndex: Int, childIndex: Int) {
        guard let group = store.item(at: groupIndex),
              group.kind == .group,
              let kids = group.children,
              kids.indices.contains(childIndex) else { return }
        Paster.shared.deliver(kids[childIndex], autoPaste: settings.autoPaste)
    }

    private func openPreferences() {
        if prefsWindow == nil {
            let root = PreferencesView(store: store,
                                       onHowTo: { [weak self] in self?.openHowTo() })
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
