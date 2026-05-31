import AppKit

/// Exports the whole history as a TextEdit-friendly **RTFD** document.
///
/// RTFD (Rich Text Format Directory) is a native macOS document format that
/// has supported inline images via `NSTextAttachment` for decades — unlike
/// Apple Notes' AppleScript-driven HTML import, which silently downgrades any
/// embedded image to a generic file attachment on current macOS.
///
/// We build an `NSAttributedString` (text rows + inline image attachments),
/// serialize it as an `.rtfd` bundle via `fileWrapper(…)`, drop it in the
/// temp dir, and `open` it — TextEdit pops up with everything inline and the
/// user can save / share / paste from there. From TextEdit, a normal ⌘A ⌘C
/// even pastes the images cleanly into Notes (it's a real native paste, not
/// AppleScript HTML).
///
/// Falls back to copying a plain-text list to the clipboard if writing fails.
enum Exporter {
    /// Resize images so the longer side is at most this many points, so a huge
    /// screenshot doesn't blow up the rendered doc.
    private static let maxImageSide: CGFloat = 480

    static func exportToTextEdit(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }

        let doc = buildAttributedString(items)
        let range = NSRange(location: 0, length: doc.length)
        guard let bundle = try? doc.fileWrapper(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        ) else {
            fallbackToClipboard(items); return
        }

        // Friendly file name with a timestamp. Live in the temp dir; macOS
        // cleans it up eventually and the user can Save As from TextEdit
        // to keep it somewhere permanent.
        let stamp = DateFormatter.localizedString(from: Date(),
                                                  dateStyle: .short,
                                                  timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip and cue — \(stamp).rtfd")

        do {
            try? FileManager.default.removeItem(at: outURL)  // overwrite if exists
            try bundle.write(to: outURL, options: .atomic, originalContentsURL: nil)
        } catch {
            NSLog("clipandcue: export write failed: \(error)")
            fallbackToClipboard(items); return
        }

        NSWorkspace.shared.open(outURL)
    }

    // MARK: Attributed string

    private static func buildAttributedString(_ items: [ClipItem]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let boldFont = NSFont.boldSystemFont(ofSize: 13)
        let mutedColor = NSColor.secondaryLabelColor

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let header = "clip and cue — \(items.count) item\(items.count == 1 ? "" : "s")\n"
                   + "\(df.string(from: Date()))\n\n"
        out.append(NSAttributedString(string: header, attributes: [.font: boldFont]))

        for (i, item) in items.enumerated() {
            out.append(NSAttributedString(string: "\(i + 1). ", attributes: [.font: boldFont]))

            switch item.kind {
            case .text, .richText:
                out.append(NSAttributedString(string: item.text ?? "",
                                              attributes: [.font: bodyFont]))
            case .files:
                let names = (item.filePaths ?? [])
                    .map { ($0 as NSString).lastPathComponent }
                    .joined(separator: ", ")
                out.append(NSAttributedString(string: names, attributes: [.font: bodyFont]))
            case .image:
                if let img = nsImage(for: item) {
                    let attach = NSTextAttachment()
                    attach.image = resize(img, maxSide: maxImageSide)
                    out.append(NSAttributedString(attachment: attach))
                } else {
                    out.append(NSAttributedString(string: "[\(item.displayPrimary)]",
                                                  attributes: [.font: bodyFont,
                                                               .foregroundColor: mutedColor]))
                }
            }
            out.append(NSAttributedString(string: "\n\n"))
        }

        return out
    }

    private static func nsImage(for item: ClipItem) -> NSImage? {
        guard let data = item.imageData else { return nil }
        return NSImage(data: data)
    }

    /// Downscale `image` so the longer side is at most `maxSide` points.
    /// Returns the original if already smaller.
    private static func resize(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        let longer = max(size.width, size.height)
        guard longer > maxSide else { return image }
        let scale = maxSide / longer
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .sourceOver, fraction: 1.0)
        scaled.unlockFocus()
        return scaled
    }

    // MARK: Fallback

    private static func fallbackToClipboard(_ items: [ClipItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(buildPlainText(items), forType: .string)
        Notifier.shared.notifyExportFallback()
    }

    private static func buildPlainText(_ items: [ClipItem]) -> String {
        var imageCount = 0
        var lines: [String] = ["clip and cue — \(items.count) item\(items.count == 1 ? "" : "s")", ""]
        for (i, item) in items.enumerated() {
            let n = i + 1
            switch item.kind {
            case .text, .richText:
                lines.append("\(n). \(item.text ?? "")")
            case .files:
                let names = (item.filePaths ?? [])
                    .map { ($0 as NSString).lastPathComponent }
                    .joined(separator: "\n    ")
                lines.append("\(n). \(names)")
            case .image:
                imageCount += 1
                lines.append("\(n). [\(item.displayPrimary)]")
            }
        }
        if imageCount > 0 {
            lines.append("")
            lines.append("(images can't be copied as text — open clip and cue to grab them)")
        }
        return lines.joined(separator: "\n")
    }
}
