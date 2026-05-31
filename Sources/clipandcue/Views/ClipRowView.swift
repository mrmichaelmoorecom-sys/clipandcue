import SwiftUI

/// A keyboard-shortcut number badge (1–9). Turns accent-filled with a pin
/// glyph when the item is pinned. When `numbered` is false, renders as a
/// blank placeholder box — used in the dropdown menu for items past slot 9
/// (which the HUD's 1–9 quick-keys can't reach).
struct NumberBadge: View {
    let number: Int
    var large: Bool = false
    var pinned: Bool = false
    var numbered: Bool = true

    var body: some View {
        Group {
            if numbered {
                Text("\(number)")
                    .font(.system(size: large ? 15 : 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Color.clear
            }
        }
            .frame(width: large ? 26 : 20, height: large ? 26 : 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(pinned ? Color.accentColor : Color.secondary.opacity(0.18))
            )
            .foregroundStyle(pinned ? Color.white : Color.secondary)
            .overlay(alignment: .topTrailing) {
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: large ? 9 : 7, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(1.5)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                        .offset(x: large ? 5 : 4, y: large ? -5 : -4)
                }
            }
    }
}

/// A single row representing one clipboard item.
struct ClipRowView: View {
    let index: Int
    let item: ClipItem
    var large: Bool = false
    /// Show the numeric label inside the badge. False in the dropdown for items
    /// past slot 9 (no 1–9 quick-key, so the number would lie).
    var numbered: Bool = true
    /// When set, the number badge becomes a button that pins/unpins the item.
    var onTogglePin: (() -> Void)? = nil

    private var thumbSide: CGFloat { large ? 40 : 26 }

    var body: some View {
        HStack(spacing: 10) {
            badge

            preview
                .frame(width: thumbSide, height: thumbSide)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayPrimary)
                    .font(large ? .body : .callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.displaySecondary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, large ? 8 : 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badge: some View {
        if let onTogglePin {
            Button(action: onTogglePin) {
                NumberBadge(number: index + 1, large: large, pinned: item.pinned, numbered: numbered)
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "Unpin" : "Pin to top")
        } else {
            NumberBadge(number: index + 1, large: large, pinned: item.pinned, numbered: numbered)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumb = item.thumbnailImage {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: large ? 20 : 14))
                .foregroundStyle(.secondary)
        }
    }
}
