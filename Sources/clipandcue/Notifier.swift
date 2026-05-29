import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for the "couldn't save" alert.
final class Notifier {
    static let shared = Notifier()

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyOversized(bytes: Int, kindLabel: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Copy not saved"
        content.body = "A \(kindLabel) of \(ClipItem.humanSize(bytes)) exceeded the size limit "
            + "and wasn't added to clipandcue."
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNoteFallback() {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Couldn't open Notes"
        content.body = "Allow clip and cue under System Settings → Privacy & Security → "
            + "Automation. For now, your list was copied to the clipboard."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
