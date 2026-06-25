import SwiftUI
import AppKit
import Carbon.HIToolbox

struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    let store: ClipStore
    var onHowTo: () -> Void = {}

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted = Paster.shared.hasAccessibility

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "Version \(v)"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                Stepper("Keep \(settings.historySize) recent items",
                        value: $settings.historySize, in: 1...AppSettings.maxHistory)
                    .onChange(of: settings.historySize) { _ in store.enforceLimit() }
                LabeledContent("Quick-paste shortcut") {
                    HotkeyRecorderView()
                }
            }

            Section("Sync") {
                Toggle("Sync with my other devices", isOn: $settings.syncEnabled)
                Text("Syncs clips through your iCloud account to your other devices running clip and cue (e.g. your iPhone). Off keeps everything on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Pasting") {
                Toggle("Paste into the active app automatically", isOn: $settings.autoPaste)
                Toggle("Paste as plain text", isOn: $settings.pasteAsPlainText)
                Text("Plain text drops fonts and colors from rich-text copies.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacy & storage") {
                Toggle("Ignore items from password managers", isOn: $settings.ignoreConcealed)
                Text("Skips copies apps flag as concealed/transient (e.g. 1Password).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Clear history when I quit", isOn: $settings.clearOnQuit)
                Stepper("Don't save items larger than \(settings.sizeCapMB) MB",
                        value: $settings.sizeCapMB, in: 1...200)
                Button("Clear history now", role: .destructive) { store.clear() }
                    .disabled(store.items.isEmpty)
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    Text(accessibilityGranted ? "Granted" : "Not granted")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Button("Open System Settings…") { openAccessibilitySettings() }
                }
                Text("Required to paste automatically into other apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("clip and cue").font(.headline)
                        Text("\(version) · CC BY-NC 4.0").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button("How clip and cue works…") { onHowTo() }
                updateRow
                HStack(spacing: 18) {
                    linkButton("Website", "https://clipandcue.com")
                    linkButton("GitHub", "https://github.com/mrmichaelmoorecom-sys/clipandcue")
                    linkButton("License", "https://creativecommons.org/licenses/by-nc/4.0/")
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
        .onAppear { accessibilityGranted = Paster.shared.hasAccessibility }
    }

    private func linkButton(_ title: String, _ urlString: String) -> some View {
        Button(title) { if let url = URL(string: urlString) { NSWorkspace.shared.open(url) } }
            .buttonStyle(.link)
            .font(.caption)
    }

    /// "Check for updates" row in About — opens the latest GitHub release
    /// page in the browser. Once we're on the Mac App Store, that channel
    /// handles update prompts automatically; this button stays useful for
    /// users who got the app via direct download.
    @ViewBuilder
    private var updateRow: some View {
        HStack(spacing: 10) {
            Button("Check for updates…") {
                if let url = URL(string: "https://github.com/mrmichaelmoorecom-sys/clipandcue/releases/latest") {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
        }
    }

    private func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Click-to-record button that captures the next modified key press and
/// writes it to AppSettings. Escape cancels, "Reset" restores ⌘⌥V.
private struct HotkeyRecorderView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(isRecording ? "Type a shortcut…" : currentDisplay)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 76)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press a key combo (Esc to cancel)" : "Click and press a key combo to change")

            if !isDefault {
                Button("Reset") { resetToDefault() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var currentDisplay: String {
        HotkeyFormatter.display(keyCode: settings.hotkeyKeyCode,
                                modifiers: settings.hotkeyModifiers)
    }

    private var isDefault: Bool {
        settings.hotkeyKeyCode == AppSettings.defaultHotkeyKeyCode &&
        settings.hotkeyModifiers == AppSettings.defaultHotkeyModifiers
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    /// Returns nil to consume the event (so it doesn't reach the rest of the UI),
    /// or the event to let it through (e.g. if it's a bare key with no modifiers).
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == kVK_Escape {
            stopRecording()
            return nil
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Require at least one modifier — otherwise we'd capture plain typing.
        guard !mods.isEmpty else { return event }
        settings.hotkeyKeyCode = Int(event.keyCode)
        settings.hotkeyModifiers = HotkeyFormatter.carbonModifiers(from: mods)
        stopRecording()
        return nil
    }

    private func resetToDefault() {
        settings.hotkeyKeyCode = AppSettings.defaultHotkeyKeyCode
        settings.hotkeyModifiers = AppSettings.defaultHotkeyModifiers
    }
}
