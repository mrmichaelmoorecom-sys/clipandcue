import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for the "couldn't save" alert.
final class Notifier {
    static let shared = Notifier()

    /// Category id for the oversized-copy notification — owns the
    /// "Open Preferences" action so the user can raise the cap with one tap.
    static let oversizedCategory = "clipandcue.oversized"
    /// Action id surfaced by `userNotificationCenter(_:didReceive:)` so the
    /// app delegate knows to open the Preferences window.
    static let openPreferencesAction = "clipandcue.openPreferences"

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// True once we've asked macOS for notification permission this launch.
    /// Authorization is requested LAZILY — the first time a notification is
    /// actually about to be shown — instead of at app launch, so a fresh
    /// install shows zero permission dialogs until one is genuinely needed.
    /// (Also keeps the App Store review notes literally true: the Store
    /// build requests nothing at launch.)
    private var didRequestAuthorization = false

    /// Register notification categories only — safe at launch, no prompt.
    func registerCategories() {
        guard available else { return }
        let openPrefs = UNNotificationAction(
            identifier: Self.openPreferencesAction,
            title: "Open Preferences",
            options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.oversizedCategory,
            actions: [openPrefs],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func requestAuthorizationIfNeeded(_ then: @escaping () -> Void) {
        guard !didRequestAuthorization else { then(); return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in then() }
    }

    func notifyOversized(bytes: Int, kindLabel: String) {
        guard available else { return }
        let capMB = AppSettings.shared.sizeCapMB
        let content = UNMutableNotificationContent()
        content.title = "Copy too big to keep"
        content.body = "A \(kindLabel) of \(ClipItem.humanSize(bytes)) exceeded the \(capMB) MB size cap "
            + "and wasn't added to clipandcue. Raise the cap in Preferences to keep larger copies."
        content.categoryIdentifier = Self.oversizedCategory
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        requestAuthorizationIfNeeded {
            UNUserNotificationCenter.current().add(request)
        }
    }

    func notifyExportFallback() {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Couldn't open the export"
        content.body = "Something prevented writing the document. "
            + "For now, your list was copied to the clipboard."
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        requestAuthorizationIfNeeded {
            UNUserNotificationCenter.current().add(request)
        }
    }
}
