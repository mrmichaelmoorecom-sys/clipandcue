import SwiftUI

/// A keyboard-shortcut number badge (1–9).
struct NumberBadge: View {
    let number: Int
    var large: Bool = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: large ? 15 : 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(width: large ? 26 : 20, height: large ? 26 : 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
            )
            .foregroundStyle(.secondary)
    }
}

/// A single row representing one clipboard item.
struct ClipRowView: View {
    let index: Int
    let item: ClipItem
    var large: Bool = false

    private var thumbSide: CGFloat { large ? 40 : 26 }

    var body: some View {
        HStack(spacing: 10) {
            NumberBadge(number: index + 1, large: large)

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
