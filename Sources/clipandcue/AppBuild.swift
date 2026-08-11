import Foundation

/// Which distribution channel this process is running under.
enum AppBuild {
    /// True when running sandboxed — every Mac App Store build is, and our
    /// Developer ID direct-download build is not. Store builds must not
    /// request Accessibility or synthesize keystrokes (guideline 2.4.5, App
    /// Review Board 2026-08), check for updates outside the Store
    /// (2.4.5(vii)), or link to external distribution channels. Everything
    /// channel-specific keys off this one flag so the two behaviors can't
    /// drift apart file by file.
    /// Decided at COMPILE time: scripts/archive_app_store.sh builds with
    /// -Xswiftc -DAPPSTORE, the Developer ID pipeline builds without it.
    /// A compile-time constant (rather than the old APP_SANDBOX_CONTAINER_ID
    /// env sniff) means the Store binary physically excludes the
    /// Accessibility/CGEvent code via #if !APPSTORE, and the direct build
    /// can't be flipped into Store mode by spoofing an env var.
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}
