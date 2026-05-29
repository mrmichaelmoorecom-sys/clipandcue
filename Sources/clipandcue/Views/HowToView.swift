import SwiftUI
import AppKit

/// A short usage guide opened from the menu's "How to" button.
struct HowToView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

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
                    Text("Nothing is uploaded anywhere. Use ")
                    + Text("Clear").bold()
                    + Text(" in the menu, or turn on ")
                    + Text("“Clear history when I quit”").bold()
                    + Text(" in Preferences, to wipe it.")
                }
            }
            .padding(22)
        }
        .frame(width: 440, height: 540)
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
        }
        .padding(.bottom, 18)
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
