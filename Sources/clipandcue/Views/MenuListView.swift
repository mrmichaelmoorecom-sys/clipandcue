import SwiftUI

/// The dropdown shown from the menu bar status item.
struct MenuListView: View {
    @ObservedObject var store: ClipStore
    var onPick: (Int) -> Void
    var onClear: () -> Void
    var onExport: () -> Void
    var onPreferences: () -> Void
    var onHowTo: () -> Void
    var onQuit: () -> Void

    @State private var hoverIndex: Int? = nil
    @State private var searchActive: Bool = false
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    /// (original-store-index, item) pairs after applying the search filter.
    /// Always carries the *unfiltered* index so the badge number stays stable
    /// and `onPick(idx)` resolves to the right item in the store.
    private var filteredEntries: [(idx: Int, item: ClipItem)] {
        let all = store.items.enumerated().map { (idx: $0.offset, item: $0.element) }
        guard searchActive, !searchText.isEmpty else { return all }
        return all.filter { entry in
            let q = searchText
            if entry.item.displayPrimary.range(of: q, options: .caseInsensitive) != nil { return true }
            if let t = entry.item.text, t.range(of: q, options: .caseInsensitive) != nil { return true }
            // Match file names for .files items.
            if let paths = entry.item.filePaths {
                for p in paths {
                    if (p as NSString).lastPathComponent.range(of: q, options: .caseInsensitive) != nil { return true }
                }
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if searchActive {
                searchField
                Divider()
            }

            if filteredEntries.isEmpty {
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
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 16, height: 16)
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search clips", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand { closeSearch() }
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredEntries, id: \.item.id) { entry in
                    ClipRowView(index: entry.idx, item: entry.item,
                                numbered: entry.idx < 9,
                                onTogglePin: { store.togglePin(id: entry.item.id) })
                        .background(hoverIndex == entry.idx
                                    ? Color.accentColor.opacity(0.15)
                                    : (entry.item.pinned ? Color.accentColor.opacity(0.08) : Color.clear))
                        .onHover { inside in
                            hoverIndex = inside ? entry.idx : (hoverIndex == entry.idx ? nil : hoverIndex)
                        }
                        .onTapGesture { onPick(entry.idx) }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private var emptyState: some View {
        let noStore = store.items.isEmpty
        let noMatches = searchActive && !searchText.isEmpty && !noStore
        return VStack(spacing: 6) {
            Image(systemName: noMatches ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(noMatches ? "No matches" : "Nothing copied yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !noMatches {
                Text("Copy something and it shows up here.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // Icon-only search toggle, left of Clear. Dark-burgundy chip so it
            // reads as a deliberate brand affordance, not a quiet footer button.
            Button(action: toggleSearch) {
                Image(systemName: searchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.30, green: 0.12, blue: 0.17))   // dark burgundy
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
            .help(searchActive ? "Close search" : "Search clips")

            FooterButton(title: "Clear", systemImage: "trash", action: onClear)
                .disabled(store.items.isEmpty)
            FooterButton(title: "Export", systemImage: "square.and.arrow.up", action: onExport)
                .disabled(store.items.isEmpty)
            Spacer()
            FooterButton(title: "How to", systemImage: "questionmark.circle", action: onHowTo)
            FooterButton(title: "Preferences", systemImage: "gearshape", action: onPreferences)
            FooterButton(title: "Quit", systemImage: "power", action: onQuit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func toggleSearch() {
        if searchActive {
            closeSearch()
        } else {
            searchActive = true
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func closeSearch() {
        searchActive = false
        searchText = ""
        searchFocused = false
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
