import Foundation
import AppKit

enum ClipKind: String, Codable {
    case text
    case richText
    case image
    case files
}

/// A single captured clipboard entry. Held fully in memory; `ClipStore`
/// decides how the large blobs (image / rtf data) are written to disk.
struct ClipItem: Identifiable {
    let id: UUID
    let kind: ClipKind
    let createdAt: Date

    // text & richText (text is the plain-text fallback, always present for those kinds)
    var text: String?
    var rtfData: Data?

    // image
    var imageData: Data?
    var imageUTType: String?   // e.g. "public.png" / "public.tiff"
    var thumbnailData: Data?
    var pixelWidth: Int?
    var pixelHeight: Int?

    // files (plain paths copied from Finder — app isn't sandboxed)
    var filePaths: [String]?

    /// Full snapshot of every type/data pair that was on the pasteboard at
    /// capture, with each individual representation capped at the user's
    /// size limit. Used by Paster to write the *exact* original pasteboard
    /// state back when the user picks this clip, so apps that own private
    /// pasteboard types (Illustrator's `com.adobe.illustrator.aip`,
    /// Keynote's `com.apple.iWork.TSPNativeObject`, etc.) get an editable
    /// paste-back instead of a flattened PDF / TIFF.
    ///
    /// Nil for:
    /// - `.files` clips (paste uses sequential file-URL ⌘V cycles instead).
    /// - Clips captured by older app versions (legacy fields are used as
    ///   the fallback paste path in `Paster.writeToPasteboard`).
    /// - Clips pulled from CloudKit (sync only carries text + image).
    var pasteboardSnapshot: [String: Data]?

    /// User-pinned (favorite): sorted to the top and protected from eviction.
    var pinned: Bool = false

    /// User-assigned name, set via the dropdown's right-click → Rename.
    /// When non-nil, overrides the computed primary label in row displays
    /// (e.g. a multi-file stack shows "Q3 hero exports" instead of
    /// "IMG_3924.png +5 more"). The underlying file paths and snapshot
    /// are untouched.
    var customLabel: String?

    init(kind: ClipKind,
         id: UUID = UUID(),
         createdAt: Date = Date(),
         text: String? = nil,
         rtfData: Data? = nil,
         imageData: Data? = nil,
         imageUTType: String? = nil,
         thumbnailData: Data? = nil,
         pixelWidth: Int? = nil,
         pixelHeight: Int? = nil,
         filePaths: [String]? = nil,
         pasteboardSnapshot: [String: Data]? = nil,
         pinned: Bool = false,
         customLabel: String? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.text = text
        self.rtfData = rtfData
        self.imageData = imageData
        self.imageUTType = imageUTType
        self.thumbnailData = thumbnailData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.filePaths = filePaths
        self.pasteboardSnapshot = pasteboardSnapshot
        self.pinned = pinned
        self.customLabel = customLabel
    }

    /// Approximate stored byte size — drives the "PNG · 27 MB" label.
    ///
    /// When `pasteboardSnapshot` exists, the legacy preview fields
    /// (`imageData`, `rtfData`, `text`) hold the *same* bytes that already
    /// live inside the snapshot dict. Summing both double-counts the heavy
    /// reps (a 27 MB TIFF reads as 54 MB), so the snapshot is the single
    /// source of truth when it's present.
    var byteSize: Int {
        var n = thumbnailData?.count ?? 0
        n += (filePaths?.reduce(0) { $0 + $1.utf8.count }) ?? 0
        if let snap = pasteboardSnapshot {
            n += snap.values.reduce(0) { $0 + $1.count }
        } else {
            n += text?.utf8.count ?? 0
            n += rtfData?.count ?? 0
            n += imageData?.count ?? 0
        }
        return n
    }

    /// Two items dedupe when their content matches.
    func sameContent(as other: ClipItem) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text, .richText:
            return text == other.text
        case .image:
            return imageData == other.imageData
        case .files:
            return filePaths == other.filePaths
        }
    }

    // MARK: Display

    /// First line, whitespace-collapsed, truncated for the list. A user-set
    /// `customLabel` always wins so renamed stacks read with their nickname.
    var displayPrimary: String {
        if let label = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        switch kind {
        case .text, .richText:
            return Self.firstLine(text ?? "", max: 60)
        case .image:
            if let w = pixelWidth, let h = pixelHeight {
                return "Image · \(w)×\(h)"
            }
            return "Image"
        case .files:
            guard let paths = filePaths, let first = paths.first else { return "Files" }
            let name = (first as NSString).lastPathComponent
            if paths.count > 1 { return "\(name)  +\(paths.count - 1) more" }
            return name
        }
    }

    /// Secondary descriptor (type / size).
    var displaySecondary: String {
        switch kind {
        case .text:
            return "Text"
        case .richText:
            return "Rich text"
        case .image:
            let ut = imageUTType ?? ""
            let ext: String
            if ut.contains("pdf") { ext = "PDF" }
            else if ut.contains("png") { ext = "PNG" }
            else if ut.contains("tiff") { ext = "TIFF" }
            else { ext = "Image" }
            return "\(ext) · \(Self.humanSize(byteSize))"
        case .files:
            return (filePaths?.count ?? 0) == 1 ? "File" : "Files"
        }
    }

    var symbolName: String {
        switch kind {
        case .text, .richText: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }

    var thumbnailImage: NSImage? {
        guard let data = thumbnailData else { return nil }
        return NSImage(data: data)
    }

    static func firstLine(_ s: String, max: Int) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = line
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let base = collapsed.isEmpty ? s.trimmingCharacters(in: .whitespacesAndNewlines) : collapsed
        if base.count > max {
            return String(base.prefix(max)) + "…"
        }
        return base
    }

    static func humanSize(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        if idx == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[idx])
    }
}
