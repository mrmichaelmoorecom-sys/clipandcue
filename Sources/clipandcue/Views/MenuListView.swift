import SwiftUI

/// The dropdown shown from the menu bar status item.
struct MenuListView: View {
    @ObservedObject var store: ClipStore
    var onPick: (Int) -> Void
    var onClear: () -> Void
    var onNewNote: () -> Void
    var onPreferences: () -> Void
    var onHowTo: () -> Void
    var onQuit: () -> Void

    @State private var hoverIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.items.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("clipandcue")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("⌘⌥V")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, item in
                    ClipRowView(index: idx, item: item)
                        .background(hoverIndex == idx ? Color.accentColor.opacity(0.15) : Color.clear)
                        .onHover { inside in hoverIndex = inside ? idx : (hoverIndex == idx ? nil : hoverIndex) }
                        .onTapGesture { onPick(idx) }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Nothing copied yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Copy something and it shows up here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            FooterButton(title: "Clear", systemImage: "trash", action: onClear)
                .disabled(store.items.isEmpty)
            FooterButton(title: "New note", systemImage: "square.and.pencil", action: onNewNote)
                .disabled(store.items.isEmpty)
            Spacer()
            FooterButton(title: "How to", systemImage: "questionmark.circle", action: onHowTo)
            FooterButton(title: "Preferences", systemImage: "gearshape", action: onPreferences)
            FooterButton(title: "Quit", systemImage: "power", action: onQuit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
