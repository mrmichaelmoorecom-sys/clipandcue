import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    let store: ClipStore

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted = Paster.shared.hasAccessibility

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                Toggle("Paste into the active app automatically", isOn: $settings.autoPaste)
            }

            Section("Capture") {
                Stepper("Maximum item size: \(settings.sizeCapMB) MB",
                        value: $settings.sizeCapMB, in: 1...200)
                Text("Copies larger than this aren't saved. You'll get a notification when that happens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear history", role: .destructive) { store.clear() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear { accessibilityGranted = Paster.shared.hasAccessibility }
    }

    private func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
