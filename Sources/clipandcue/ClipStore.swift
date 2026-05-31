import Foundation
import Combine

/// Ordered, capped history of clipboard items (newest first), persisted to disk.
final class ClipStore: ObservableObject {
    static let maxItems = 50

    @Published private(set) var items: [ClipItem] = []

    private let supportDir: URL
    private let blobsDir: URL
    private let historyURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDir = base.appendingPathComponent("clipandcue", isDirectory: true)
        blobsDir = supportDir.appendingPathComponent("blobs", isDirectory: true)
        historyURL = supportDir.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Mutations

    /// Effective cap: user's preference, clamped to the hard maximum.
    private var limit: Int { min(Self.maxItems, max(1, AppSettings.shared.historySize)) }

    /// Insert a new item at the top of the unpinned section (pinned items stay
    /// above it), deduping identical content and capping the list.
    func add(_ item: ClipItem) {
        // Preserve pin state if we already had this exact content.
        let wasPinned = items.first { $0.sameContent(as: item) }?.pinned ?? false
        items.removeAll { $0.sameContent(as: item) }
        var item = item
        item.pinned = wasPinned
        let insertAt = item.pinned ? 0 : (items.firstIndex { !$0.pinned } ?? items.count)
        items.insert(item, at: insertAt)
        enforceCap()
        scheduleSave()
    }

    /// Pin/unpin an item. Pinning jumps it to the very top; unpinning drops it
    /// to the top of the unpinned section. Pinned items survive eviction.
    func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var it = items.remove(at: idx)
        it.pinned.toggle()
        if it.pinned {
            items.insert(it, at: 0)
        } else {
            let at = items.firstIndex { !$0.pinned } ?? items.count
            items.insert(it, at: at)
        }
        scheduleSave()
    }

    /// Trim to the current history-size preference (call after the user changes it).
    func enforceLimit() {
        guard items.count > limit else { return }
        enforceCap()
        scheduleSave()
    }

    /// Drop oldest *unpinned* items until within the limit (pinned are protected).
    private func enforceCap() {
        while items.count > limit, let idx = items.lastIndex(where: { !$0.pinned }) {
            items.remove(at: idx)
        }
        if items.count > limit { items = Array(items.prefix(limit)) }
    }

    func clear() {
        items.removeAll()
        scheduleSave()
    }

    /// Synchronously wipe in-memory items and on-disk data (used on quit).
    func purgePersistedNow() {
        items.removeAll()
        saveWorkItem?.cancel()
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: blobsDir)
    }

    func item(at index: Int) -> ClipItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    // MARK: Persistence

    private struct PersistedItem: Codable {
        let id: UUID
        let kind: ClipKind
        let createdAt: Date
        let text: String?
        let imageUTType: String?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let filePaths: [String]?
        let hasImageData: Bool
        let hasThumbnail: Bool
        let hasRTF: Bool
        let pinned: Bool?   // optional for backward-compat with pre-pin history.json
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func blobURL(_ id: UUID, _ ext: String) -> URL {
        blobsDir.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    private func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)

        var keep = Set<String>()
        var dtos: [PersistedItem] = []

        for item in items {
            if let data = item.imageData {
                let url = blobURL(item.id, "full")
                try? data.write(to: url, options: .atomic)
                keep.insert(url.lastPathComponent)
            }
            if let data = item.thumbnailData {
                let url = blobURL(item.id, "thumb")
                try? data.write(to: url, options: .atomic)
                keep.insert(url.lastPathComponent)
            }
            if let data = item.rtfData {
                let url = blobURL(item.id, "rtf")
                try? data.write(to: url, options: .atomic)
                keep.insert(url.lastPathComponent)
            }
            dtos.append(PersistedItem(
                id: item.id,
                kind: item.kind,
                createdAt: item.createdAt,
                text: item.text,
                imageUTType: item.imageUTType,
                pixelWidth: item.pixelWidth,
                pixelHeight: item.pixelHeight,
                filePaths: item.filePaths,
                hasImageData: item.imageData != nil,
                hasThumbnail: item.thumbnailData != nil,
                hasRTF: item.rtfData != nil,
                pinned: item.pinned))
        }

        // Drop orphaned blob files.
        if let existing = try? fm.contentsOfDirectory(at: blobsDir, includingPropertiesForKeys: nil) {
            for url in existing where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }

        if let data = try? JSONEncoder().encode(dtos) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let dtos = try? JSONDecoder().decode([PersistedItem].self, from: data) else {
            return
        }
        items = dtos.map { dto in
            ClipItem(
                kind: dto.kind,
                id: dto.id,
                createdAt: dto.createdAt,
                text: dto.text,
                rtfData: dto.hasRTF ? (try? Data(contentsOf: blobURL(dto.id, "rtf"))) : nil,
                imageData: dto.hasImageData ? (try? Data(contentsOf: blobURL(dto.id, "full"))) : nil,
                imageUTType: dto.imageUTType,
                thumbnailData: dto.hasThumbnail ? (try? Data(contentsOf: blobURL(dto.id, "thumb"))) : nil,
                pixelWidth: dto.pixelWidth,
                pixelHeight: dto.pixelHeight,
                filePaths: dto.filePaths,
                pinned: dto.pinned ?? false)
        }
    }
}
