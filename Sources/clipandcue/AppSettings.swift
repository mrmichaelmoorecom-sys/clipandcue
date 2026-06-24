import Foundation
import Combine
import Carbon.HIToolbox

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
        static let syncEnabled = "syncEnabled"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
    }

    /// The factory default — ⌘⌥V.
    static let defaultHotkeyKeyCode = kVK_ANSI_V
    static let defaultHotkeyModifiers = Int(cmdKey | optionKey)

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

    /// Sync text/image clips to the user's other devices via CloudKit.
    @Published var syncEnabled: Bool {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: Keys.syncEnabled) }
    }

    /// Quick-paste hotkey — the virtual key code (Carbon kVK_*).
    @Published var hotkeyKeyCode: Int {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    /// Quick-paste hotkey — the modifier mask (Carbon cmdKey | optionKey | …).
    @Published var hotkeyModifiers: Int {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.sizeCapMB: 20,
            Keys.autoPaste: true,
            Keys.historySize: 9,
            Keys.pasteAsPlainText: false,
            // Privacy defaults (v0.2.4): both off-by-default so a fresh
            // install never touches the network or captures password-manager
            // copies until the user explicitly opts in via Preferences.
            Keys.ignoreConcealed: true,
            Keys.clearOnQuit: false,
            Keys.syncEnabled: false,
            Keys.hotkeyKeyCode: Self.defaultHotkeyKeyCode,
            Keys.hotkeyModifiers: Self.defaultHotkeyModifiers
        ])
        sizeCapMB = d.integer(forKey: Keys.sizeCapMB)
        autoPaste = d.bool(forKey: Keys.autoPaste)
        historySize = min(Self.maxHistory, max(1, d.integer(forKey: Keys.historySize)))
        pasteAsPlainText = d.bool(forKey: Keys.pasteAsPlainText)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        clearOnQuit = d.bool(forKey: Keys.clearOnQuit)
        syncEnabled = d.bool(forKey: Keys.syncEnabled)
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
    }

    var sizeCapBytes: Int { sizeCapMB * 1024 * 1024 }
}
