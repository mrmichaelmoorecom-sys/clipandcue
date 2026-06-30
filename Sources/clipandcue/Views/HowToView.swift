import SwiftUI
import AppKit

/// A short usage guide opened from the menu's "How to" button. Split into
/// two segmented tabs — the **Basics** tab covers the everyday flow
/// (copy, menu, hotkey, pin, accessibility, privacy) and the **Advanced**
/// tab covers the power-user features (multi-file stacks, user-built
/// stacks) plus the contact line.
struct HowToView: View {
    @State private var tab: Tab = .basics

    enum Tab: Hashable { case basics, advanced }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 22)

            Picker("", selection: $tab) {
                Text("Basics").tag(Tab.basics)
                Text("Advanced").tag(Tab.advanced)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .basics: basics
                    case .advanced: advanced
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 440, height: 600)
    }

    // MARK: Basics

    @ViewBuilder
    private var basics: some View {
        stepCard(symbol: "doc.on.clipboard", title: "Copy like you always do") {
            Text("Every time you press ") + kbd("⌘C") + Text(", clip and cue quietly remembers it — text, images, and copied files. Your most recent copies sit at the top.")
        }

        stepCard(symbol: "paperclip", title: "Open from the menu bar") {
            Text("Click the paperclip in the menu bar to see your recent copies. Click any row to paste it into whatever app you were just using.")
        }

        stepCard(symbol: "command", title: "Quick-paste with the keyboard") {
            Group {
                Text("Press ") + kbd("⌘⌥V") + Text(" anywhere to pop up the list, then:")
            }
            VStack(alignment: .leading, spacing: 4) {
                bullet { kbd("1") + Text("–") + kbd("9") + Text(" pastes that item") }
                bullet { kbd("↑") + Text(" / ") + kbd("↓") + Text(" then ") + kbd("⏎") + Text(" to choose") }
                bullet { kbd("esc") + Text(" to dismiss") }
            }
            .padding(.top, 2)
        }

        stepCard(symbol: "pin", title: "Pin your favorites") {
            Text("Click the ")
            + Text("number badge").bold()
            + Text(" on a row in the menu to pin it — pinned items jump to the top and stay there, even as you keep copying. Click the badge again to unpin.")
        }

        stepCard(symbol: "hand.raised", title: "First time: allow pasting") {
            Text("To paste into other apps, macOS asks you to allow clip and cue under ")
            + Text("System Settings → Privacy & Security → Accessibility").bold()
            + Text(". Until then, picking an item just copies it for you to paste with ") + kbd("⌘V") + Text(".")
        }

        stepCard(symbol: "lock", title: "Your history stays on your Mac") {
            Text("By default nothing is uploaded — your history lives in this Mac's Application Support folder. Use ")
            + Text("Clear").bold()
            + Text(" in the menu, or turn on ")
            + Text("“Clear history when I quit”").bold()
            + Text(" in Preferences, to wipe it.\n\nOpt-in iCloud sync is available in Preferences if you want clips to follow you across your Macs.")
        }
    }

    // MARK: Advanced

    @ViewBuilder
    private var advanced: some View {
        stepCard(symbol: "rectangle.stack", title: "Stacks for multi-file copies") {
            Text("Copy several files in Finder and clip and cue shows them as one row with a ")
            + Text("chevron").bold()
            + Text(" on the right. Click the chevron to fan out the individual files — each one previews and clicks-to-paste on its own. Click the parent row to paste them all in one go.")
        }

        stepCard(symbol: "square.stack.3d.up", title: "Build your own stacks") {
            Text("Inside the menu bar dropdown, drag any clip onto another to combine them — text, images, files, Keynote shapes, whatever — into one stack that behaves like a multi-file row. ")
            + Text("Click the chevron").bold()
            + Text(" to fan out the children, or click the parent row to paste them all in order. Drop more clips onto the stack to grow it. Right-click → ")
            + Text("Rename").bold()
            + Text(" to give it a name, or ")
            + Text("Ungroup").bold()
            + Text(" to flatten it back out.")
        }

        stepCard(symbol: "key.fill", title: "Password-manager copies") {
            Text("Out of the box, clip and cue ignores anything 1Password, Keychain, your browser, or other password tools mark as ")
            + Text("concealed").italic()
            + Text(" — passwords and TOTP codes never reach the history. If you'd rather capture every copy (including those), turn ")
            + Text("Ignore items from password managers").bold()
            + Text(" off in ") + Text("Preferences").bold() + Text(". Heads-up: captured passwords sit unencrypted on disk under your user Library, and travel to your other Macs if you also have iCloud sync on.")
        }

        contactFooter
    }

    private var contactFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text("Bugs, ideas, hellos:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("mike@toyrobotmedia.com",
                 destination: URL(string: "mailto:mike@toyrobotmedia.com")!)
                .font(.caption)
        }
        .padding(.top, 18)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("How to use clip and cue")
                    .font(.title2.bold())
                Text("Copy now. Paste later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("v\(appVersion)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
        .padding(.bottom, 14)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    @ViewBuilder
    private func stepCard<Content: View>(symbol: String, title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                VStack(alignment: .leading, spacing: 4) { content() }
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        Divider()
    }

    @ViewBuilder
    private func bullet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.tertiary)
            content()
        }
    }

    private func kbd(_ s: String) -> Text {
        Text(" \(s) ")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
    }
}
