import SwiftUI
import AppKit

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
                    Text("⌘⌥V").foregroundStyle(.secondary)
                }
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

    private func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
