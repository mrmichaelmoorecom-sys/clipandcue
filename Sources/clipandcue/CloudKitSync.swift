import Foundation
import CloudKit

/// Mirrors the iOS app's CloudKit schema so text clips sync between this Mac
/// and the user's iPhone through their **private** CloudKit database.
///
/// Text-only by design: images, files, and rich text don't map to the iOS
/// text keyboard, so only the plain-text payload crosses the wire (rich text
/// sends its text fallback). One record per clip, keyed by the clip's UUID,
/// matching `iCloud.com.clipandcue.shared` / record type `Clip` on iOS.
///
/// All operations are gated on an available iCloud account and are
/// best-effort: failures are swallowed, and the next launch's `pull` plus
/// per-capture `push` reconcile anything that didn't land.
final class MacCloudKitSync {
    static let containerID = "iCloud.com.clipandcue.shared"
    static let recordType = "Clip"

    private let database: CKDatabase

    init() {
        database = CKContainer(identifier: Self.containerID).privateCloudDatabase
    }

    /// Cheap proxy for "iCloud is usable on this Mac" — avoids touching
    /// CloudKit when the user isn't signed in.
    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Push one captured text clip so it reaches the iPhone promptly.
    func push(id: UUID, text: String, createdAt: Date) {
        guard iCloudAvailable else { return }
        Task {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            let record = CKRecord(recordType: Self.recordType, recordID: recordID)
            record["text"] = text as CKRecordValue
            record["createdAt"] = createdAt as CKRecordValue
            _ = try? await database.modifyRecords(saving: [record], deleting: [])
        }
    }

    /// Pull recent remote clips and merge genuinely-new ones into the store.
    /// Skips clips whose content the store already has, so an existing item is
    /// never reordered to the top by a routine sync.
    @MainActor
    func pull(into store: ClipStore) async {
        guard iCloudAvailable else { return }
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let matches = try? await database.records(
            matching: query, resultsLimit: ClipStore.maxItems).matchResults else { return }

        for (_, result) in matches {
            guard case .success(let record) = result,
                  let text = record["text"] as? String,
                  let createdAt = record["createdAt"] as? Date,
                  let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let candidate = ClipItem(kind: .text, id: id, createdAt: createdAt, text: text)
            if store.items.contains(where: { $0.sameContent(as: candidate) }) { continue }
            store.add(candidate)
        }
    }
}
