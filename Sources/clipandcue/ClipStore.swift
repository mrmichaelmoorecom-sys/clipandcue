import Foundation
import Combine

/// Ordered, capped history of clipboard items (newest first), persisted to disk.
final class ClipStore: ObservableObject {
    static let maxItems = 50

    @Published private(set) var items: [ClipItem] = []

    /// Fired when the history is cleared/purged, so the app can also delete the
    /// clips from CloudKit (otherwise cleared clips linger in the cloud).
    var onClear: (() -> Void)?

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

    /// Set or clear a user-assigned label for `id`. Pass nil/empty to revert
    /// to the computed default (e.g. "IMG_3924.png +5 more"). Position in
    /// the list is untouched.
    func setLabel(id: UUID, label: String?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].customLabel = (trimmed?.isEmpty == false) ? trimmed : nil
        scheduleSave()
    }

    /// Drag-to-group: combine `droppedID` into `targetID`. If the target
    /// is already a group, the dropped item is appended to its children;
    /// otherwise a fresh `.group` clip is created in the target's slot
    /// holding `[target, dropped]`. The dropped clip's pinned + position
    /// are dropped; the new group inherits the target's pinned state.
    /// One-level enforcement: if the dropped item is itself a group, its
    /// children are flattened in.
    func groupItems(droppedID: UUID, ontoTargetID targetID: UUID) {
        guard droppedID != targetID,
              let droppedIdx = items.firstIndex(where: { $0.id == droppedID }),
              let initialTargetIdx = items.firstIndex(where: { $0.id == targetID }) else { return }
        let dropped = items[droppedIdx]
        items.remove(at: droppedIdx)
        // Removing the dropped item shifts the target's index if it was below.
        let targetIdx = (droppedIdx < initialTargetIdx) ? initialTargetIdx - 1 : initialTargetIdx
        let target = items[targetIdx]

        let droppedChildren = (dropped.kind == .group) ? (dropped.children ?? []) : [dropped]

        if target.kind == .group {
            var updated = target
            updated.children = (target.children ?? []) + droppedChildren
            items[targetIdx] = updated
        } else {
            var newGroup = ClipItem(
                kind: .group,
                children: [target] + droppedChildren,
                pinned: target.pinned)
            // Preserve the target's custom label on the new group.
            newGroup.customLabel = target.customLabel
            items[targetIdx] = newGroup
        }
        scheduleSave()
    }

    /// Flatten a group back into top-level rows at the group's position,
    /// newest-on-top order preserved. Pinned state of the group is
    /// dropped; children come back unpinned (they can be re-pinned).
    func ungroupItem(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].kind == .group,
              let kids = items[idx].children, !kids.isEmpty else { return }
        items.remove(at: idx)
        items.insert(contentsOf: kids, at: idx)
        enforceCap()
        scheduleSave()
    }

    /// Paste a single child of a group at `groupID`. Returns the resolved
    /// child if it exists, so AppDelegate can hand it to Paster.
    func child(groupID: UUID, childIndex: Int) -> ClipItem? {
        guard let group = items.first(where: { $0.id == groupID }),
              group.kind == .group,
              let kids = group.children,
              kids.indices.contains(childIndex) else { return nil }
        return kids[childIndex]
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
        onClear?()
    }

    /// Synchronously wipe in-memory items and on-disk data (used on quit).
    func purgePersistedNow() {
        items.removeAll()
        saveWorkItem?.cancel()
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: blobsDir)
        onClear?()
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
        /// True when a `<id>.snap` blob (binary plist of the full
        /// pasteboard type→data dict) exists alongside the other blobs.
        /// Absent in pre-v0.2.6 history.json files.
        let hasSnapshot: Bool?
        /// User-assigned label (right-click → Rename). Optional for
        /// backward-compat with older history.json files.
        let customLabel: String?
        /// `.group` only — recursive child list. Each child carries its
        /// own blobs (snap / thumb / image / rtf) keyed by its own UUID
        /// alongside top-level items in `blobs/`. Optional for
        /// backward-compat with pre-group history.json.
        let children: [PersistedItem]?
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
        let dtos = items.map { persist($0, keep: &keep) }

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

    /// Write `item`'s blobs and produce a `PersistedItem` describing them.
    /// Recurses into `.group` children so each child's snap/thumb/etc.
    /// land in the same flat `blobs/` directory keyed by their own UUIDs.
    private func persist(_ item: ClipItem, keep: inout Set<String>) -> PersistedItem {
        let hasSnapshot = (item.pasteboardSnapshot?.isEmpty == false)

        // Skip the duplicate .full / .rtf blobs when a snapshot exists —
        // those bytes already live inside the snapshot plist.
        if !hasSnapshot, let data = item.imageData {
            let url = blobURL(item.id, "full")
            try? data.write(to: url, options: .atomic)
            keep.insert(url.lastPathComponent)
        }
        if let data = item.thumbnailData {
            let url = blobURL(item.id, "thumb")
            try? data.write(to: url, options: .atomic)
            keep.insert(url.lastPathComponent)
        }
        if !hasSnapshot, let data = item.rtfData {
            let url = blobURL(item.id, "rtf")
            try? data.write(to: url, options: .atomic)
            keep.insert(url.lastPathComponent)
        }
        if let snap = item.pasteboardSnapshot, !snap.isEmpty,
           let snapData = try? PropertyListSerialization.data(
                fromPropertyList: snap, format: .binary, options: 0) {
            let url = blobURL(item.id, "snap")
            try? snapData.write(to: url, options: .atomic)
            keep.insert(url.lastPathComponent)
        }

        let childDtos = item.children?.map { persist($0, keep: &keep) }

        return PersistedItem(
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
            pinned: item.pinned,
            hasSnapshot: hasSnapshot ? true : nil,
            customLabel: item.customLabel,
            children: childDtos)
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let dtos = try? JSONDecoder().decode([PersistedItem].self, from: data) else {
            return
        }
        items = dtos.map { rehydrate($0) }
    }

    /// Rebuild a `ClipItem` from a `PersistedItem` — reads blobs, derives
    /// preview reps from the snapshot when present, recurses into group
    /// children.
    private func rehydrate(_ dto: PersistedItem) -> ClipItem {
        // Snapshot is the source of truth when present — image and RTF
        // bytes live inside it, not in standalone .full / .rtf blobs.
        // (Clips written by older versions still use the standalone
        // blobs; we read both paths to handle the upgrade case.)
        let snapshot: [String: Data]?
        let imageData: Data?
        let rtfData: Data?
        if dto.hasSnapshot == true,
           let snap = Self.loadSnapshot(id: dto.id, blobsDir: blobsDir) {
            snapshot = snap
            imageData = Self.imageDataFromSnapshot(snap, utType: dto.imageUTType)
            rtfData = snap["public.rtf"]
        } else {
            snapshot = nil
            imageData = dto.hasImageData ? (try? Data(contentsOf: blobURL(dto.id, "full"))) : nil
            rtfData = dto.hasRTF ? (try? Data(contentsOf: blobURL(dto.id, "rtf"))) : nil
        }
        let children = dto.children?.map { rehydrate($0) }
        return ClipItem(
            kind: dto.kind,
            id: dto.id,
            createdAt: dto.createdAt,
            text: dto.text,
            rtfData: rtfData,
            imageData: imageData,
            imageUTType: dto.imageUTType,
            thumbnailData: dto.hasThumbnail ? (try? Data(contentsOf: blobURL(dto.id, "thumb"))) : nil,
            pixelWidth: dto.pixelWidth,
            pixelHeight: dto.pixelHeight,
            filePaths: dto.filePaths,
            pasteboardSnapshot: snapshot,
            children: children,
            pinned: dto.pinned ?? false,
            customLabel: dto.customLabel)
    }

    /// Pull whatever image rep matches the dto's `imageUTType` from the
    /// snapshot dict — keeps CloudKit sync working (which reads `imageData`)
    /// without storing a duplicate `.full` blob on disk.
    private static func imageDataFromSnapshot(_ snap: [String: Data],
                                              utType: String?) -> Data? {
        if let ut = utType, let d = snap[ut] { return d }
        // Fall back to the priority order ClipboardMonitor used at capture.
        return snap["com.adobe.pdf"]
            ?? snap["public.png"]
            ?? snap["public.tiff"]
            ?? snap["public.jpeg"]
    }

    private static func loadSnapshot(id: UUID, blobsDir: URL) -> [String: Data]? {
        let url = blobsDir.appendingPathComponent("\(id.uuidString).snap")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
              let dict = plist as? [String: Data] else { return nil }
        return dict
    }
}
