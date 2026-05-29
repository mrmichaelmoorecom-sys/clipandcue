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

    // files (security-scoped paths copied from Finder)
    var filePaths: [String]?

    /// User-pinned (favorite): sorted to the top and protected from eviction.
    var pinned: Bool = false

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
         pinned: Bool = false) {
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
        self.pinned = pinned
    }

    /// Approximate stored byte size, used for the size cap.
    var byteSize: Int {
        var n = 0
        n += text?.utf8.count ?? 0
        n += rtfData?.count ?? 0
        n += imageData?.count ?? 0
        n += thumbnailData?.count ?? 0
        n += (filePaths?.reduce(0) { $0 + $1.utf8.count }) ?? 0
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

    /// First line, whitespace-collapsed, truncated for the list.
    var displayPrimary: String {
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
            let ext = (imageUTType?.contains("png") ?? false) ? "PNG" : "Image"
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
