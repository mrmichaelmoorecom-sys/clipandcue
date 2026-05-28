import Foundation
import Combine

/// User-tunable preferences backed by UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let sizeCapMB = "sizeCapMB"
        static let autoPaste = "autoPaste"
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

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [Keys.sizeCapMB: 20, Keys.autoPaste: true])
        sizeCapMB = d.integer(forKey: Keys.sizeCapMB)
        autoPaste = d.bool(forKey: Keys.autoPaste)
    }

    var sizeCapBytes: Int { sizeCapMB * 1024 * 1024 }
}
