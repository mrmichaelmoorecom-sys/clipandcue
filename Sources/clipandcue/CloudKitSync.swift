import Foundation
import AppKit
import CloudKit

/// Mirrors the iOS app's CloudKit schema so clips sync between this Mac and the
/// user's iPhone through their **private** CloudKit database.
///
/// Syncs text and image clips (rich text travels as its plain-text fallback;
/// file clips aren't synced). One record per clip, keyed by UUID, matching
/// `iCloud.com.clipandcue.shared` / record type `Clip`: fields `kind` (String),
/// `createdAt` (Date), `text` (String) for text, `image` (CKAsset) for images.
///
/// Gated on an available iCloud account; all operations are best-effort.
final class MacCloudKitSync {
    static let containerID = "iCloud.com.clipandcue.shared"
    static let recordType = "Clip"

    private let database: CKDatabase

    init() {
        database = CKContainer(identifier: Self.containerID).privateCloudDatabase
    }

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// User preference (Preferences → "Sync with my other devices").
    private var syncEnabled: Bool { AppSettings.shared.syncEnabled }

    /// Push one captured clip so it reaches the iPhone promptly.
    func push(_ item: ClipItem) {
        guard syncEnabled, iCloudAvailable, let record = Self.record(from: item) else { return }
        Task { _ = try? await database.modifyRecords(saving: [record], deleting: []) }
    }

    /// Pull recent remote clips and merge genuinely-new ones into the store.
    @MainActor
    func pull(into store: ClipStore) async {
        guard syncEnabled, iCloudAvailable else { return }
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let matches = try? await database.records(
            matching: query, resultsLimit: ClipStore.maxItems).matchResults else { return }

        for (_, result) in matches {
            guard case .success(let record) = result,
                  let candidate = Self.clipItem(from: record) else { continue }
            if store.items.contains(where: { $0.sameContent(as: candidate) }) { continue }
            store.add(candidate)
        }
    }

    // MARK: Record <-> ClipItem

    private static func record(from item: ClipItem) -> CKRecord? {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["createdAt"] = item.createdAt as CKRecordValue

        switch item.kind {
        case .text, .richText:
            guard let text = item.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            record["kind"] = "text" as CKRecordValue
            record["text"] = text as CKRecordValue
        case .image:
            guard let data = item.imageData else { return nil }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(item.id.uuidString).img")
            guard (try? data.write(to: tmp, options: .atomic)) != nil else { return nil }
            record["kind"] = "image" as CKRecordValue
            record["image"] = CKAsset(fileURL: tmp)
        case .files:
            return nil  // not synced to the text-and-image iOS app
        }
        return record
    }

    private static func clipItem(from record: CKRecord) -> ClipItem? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let createdAt = record["createdAt"] as? Date else { return nil }
        let kind = record["kind"] as? String ?? "text"

        if kind == "image",
           let asset = record["image"] as? CKAsset,
           let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            let image = NSImage(data: data)
            let size = image.flatMap(ImageUtils.pixelSize)
            return ClipItem(
                kind: .image,
                id: id,
                createdAt: createdAt,
                imageData: data,
                imageUTType: "public.png",
                thumbnailData: image.flatMap { ImageUtils.thumbnailPNG(from: $0, maxDimension: 96) },
                pixelWidth: size?.width,
                pixelHeight: size?.height)
        }

        guard let text = record["text"] as? String else { return nil }
        return ClipItem(kind: .text, id: id, createdAt: createdAt, text: text)
    }
}
