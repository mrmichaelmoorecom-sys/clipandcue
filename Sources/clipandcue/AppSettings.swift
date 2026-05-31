import Foundation
import Combine

/// User-tunable preferences backed by UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Hard ceiling on how many items the store may hold.
    /// The HUD's 1–9 quick-paste keys still only address the top 9; anything
    /// beyond that is reached via search or ↑/↓ + ⏎.
    static let maxHistory = 50

    private enum Keys {
        static let sizeCapMB = "sizeCapMB"
        static let autoPaste = "autoPaste"
        static let historySize = "historySize"
        static let pasteAsPlainText = "pasteAsPlainText"
        static let ignoreConcealed = "ignoreConcealed"
        static let clearOnQuit = "clearOnQuit"
    }

    /// Per-item storage cap in megabytes. Items larger than this are not saved.
    @Published var sizeCapMB: Int {
        didSet { UserDefaults.standard.set(sizeCapMB, forKey: Keys.sizeCapMB) }
    }

    /// When true, picking an item synthesizes ⌘V into the active app.
    /// When false (or Accessibility is denied), the item is only placed on the clipboard.
    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: Keys.autoPaste) }
    }

    /// How many recent items to keep (1...9). Clamped at read time and by the
    /// stepper's range — never self-assign here (that recurses via @Published).
    @Published var historySize: Int {
        didSet { UserDefaults.standard.set(historySize, forKey: Keys.historySize) }
    }

    /// Strip formatting when pasting — rich text goes in as plain text.
    @Published var pasteAsPlainText: Bool {
        didSet { UserDefaults.standard.set(pasteAsPlainText, forKey: Keys.pasteAsPlainText) }
    }

    /// Skip items flagged concealed/transient by password managers.
    @Published var ignoreConcealed: Bool {
        didSet { UserDefaults.standard.set(ignoreConcealed, forKey: Keys.ignoreConcealed) }
    }

    /// Wipe the on-disk history when the app quits.
    @Published var clearOnQuit: Bool {
        didSet { UserDefaults.standard.set(clearOnQuit, forKey: Keys.clearOnQuit) }
    }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.sizeCapMB: 20,
            Keys.autoPaste: true,
            Keys.historySize: 9,
            Keys.pasteAsPlainText: false,
            Keys.ignoreConcealed: false,
            Keys.clearOnQuit: false
        ])
        sizeCapMB = d.integer(forKey: Keys.sizeCapMB)
        autoPaste = d.bool(forKey: Keys.autoPaste)
        historySize = min(Self.maxHistory, max(1, d.integer(forKey: Keys.historySize)))
        pasteAsPlainText = d.bool(forKey: Keys.pasteAsPlainText)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        clearOnQuit = d.bool(forKey: Keys.clearOnQuit)
    }

    var sizeCapBytes: Int { sizeCapMB * 1024 * 1024 }
}
