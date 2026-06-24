import SwiftUI
import Combine

/// Shared selection state between the HUD view and its controller.
final class QuickPasteModel: ObservableObject {
    @Published var selection: Int = 0
}

/// Floating panel shown on ⌘⌥V.
struct QuickPasteHUDView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: QuickPasteModel
    var onPick: (Int) -> Void
    /// Paste a single file out of a multi-file clip — `(itemIdx, fileIdx)`.
    var onPickFile: (Int, Int) -> Void

    /// Item ids whose multi-file sub-list is currently expanded.
    @State private var expandedItems: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.items.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, item in
                                let multi = Self.isMultiFile(item)
                                let expanded = expandedItems.contains(item.id)
                                VStack(spacing: 0) {
                                    ClipRowView(index: idx, item: item, large: true,
                                                numbered: idx < 9,
                                                isExpanded: expanded,
                                                onToggleExpand: multi ? { toggleExpand(item.id) } : nil,
                                                onPick: { onPick(idx) })
                                        .id(idx)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(idx == model.selection
                                                      ? Color.accentColor.opacity(0.28)
                                                      : (item.pinned ? Color.accentColor.opacity(0.10) : Color.clear))
                                        )
                                        .contentShape(Rectangle())

                                    if multi && expanded, let paths = item.filePaths {
                                        VStack(spacing: 0) {
                                            ForEach(Array(paths.enumerated()), id: \.offset) { (fi, path) in
                                                FileSubRowView(path: path, large: true) {
                                                    onPickFile(idx, fi)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(Color.white.opacity(0.06))
                                        )
                                        .padding(.top, 2)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    // Caps the HUD at exactly 9 large rows visible. Items past
                    // 9 are reachable via ↑/↓ or scroll (their badges are
                    // blank — the 1–9 keys can't paste them anyway).
                    .frame(maxHeight: 545)
                    .onChange(of: model.selection) { newSel in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newSel, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("Paste from clipandcue")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("1–9 · ↑↓ · ⏎ · esc")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Nothing copied yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private static func isMultiFile(_ item: ClipItem) -> Bool {
        item.kind == .files && (item.filePaths?.count ?? 0) > 1
    }

    private func toggleExpand(_ id: UUID) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems.insert(id)
        }
    }
}
