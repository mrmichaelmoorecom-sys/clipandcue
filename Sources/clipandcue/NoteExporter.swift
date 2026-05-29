import AppKit

/// Collects the whole history into a single new note in the Notes app.
/// Text/rich-text becomes text; files/folders become their names; images are
/// embedded (Notes ingests a base64 data-URI as an image attachment).
///
/// Runs in-process via NSAppleScript (so Automation permission is attributed to
/// clip and cue, paired with NSAppleEventsUsageDescription) and reads the body
/// from a temp file so large embedded images don't bloat the script source.
/// Falls back to copying a plain-text list to the clipboard if Notes is unreachable.
enum NoteExporter {
    /// Skip embedding images whose PNG exceeds this (keeps the note + main thread sane).
    private static let maxEmbedBytes = 6_000_000

    static func exportToNewNote(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }

        let html = buildHTML(items)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipandcue-note-\(UUID().uuidString).html")
        guard (try? html.write(to: tmp, atomically: true, encoding: .utf8)) != nil else {
            fallbackToClipboard(items); return
        }

        let escapedPath = tmp.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        set fh to open for access (POSIX file "\(escapedPath)")
        set txt to (read fh as «class utf8»)
        close access fh
        tell application "Notes"
            activate
            make new note with properties {body:txt}
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        try? FileManager.default.removeItem(at: tmp)

        if let errorInfo {
            NSLog("clipandcue: New note failed (\(errorInfo[NSAppleScript.errorNumber] ?? "?")): "
                  + "\(errorInfo[NSAppleScript.errorMessage] ?? "")")
            fallbackToClipboard(items)
        }
    }

    private static func fallbackToClipboard(_ items: [ClipItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(buildPlainText(items), forType: .string)
        Notifier.shared.notifyNoteFallback()
    }

    private static func buildHTML(_ items: [ClipItem]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var skipped = 0
        var rows: [String] = []

        for (i, item) in items.enumerated() {
            let n = i + 1
            switch item.kind {
            case .text, .richText:
                let lines = (item.text ?? "")
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { esc(String($0)) }
                    .joined(separator: "<br>")
                rows.append("<div><b>\(n).</b> \(lines)</div>")
            case .files:
                let names = (item.filePaths ?? [])
                    .map { esc(($0 as NSString).lastPathComponent) }
                    .joined(separator: "<br>")
                rows.append("<div><b>\(n).</b> \(names)</div>")
            case .image:
                if let b64 = pngBase64(item) {
                    rows.append("<div><b>\(n).</b></div>"
                                + "<div><img src=\"data:image/png;base64,\(b64)\"></div>")
                } else {
                    skipped += 1
                    rows.append("<div><b>\(n).</b> <i>(image not included)</i></div>")
                }
            }
        }

        var html = "<div><b>clip and cue — \(items.count) item\(items.count == 1 ? "" : "s")</b></div>"
        html += "<div>\(esc(df.string(from: Date())))</div><div><br></div>"
        html += rows.joined(separator: "<div><br></div>")
        if skipped > 0 {
            html += "<div><br></div><div><i>(\(skipped) image\(skipped == 1 ? "" : "s") "
                  + "too large to embed)</i></div>"
        }
        return html
    }

    /// PNG base64 for an image item, or nil if it can't be encoded / is too large.
    private static func pngBase64(_ item: ClipItem) -> String? {
        guard let data = item.imageData else { return nil }
        let png: Data
        if item.imageUTType?.contains("png") == true {
            png = data
        } else if let rep = NSBitmapImageRep(data: data),
                  let p = rep.representation(using: .png, properties: [:]) {
            png = p
        } else {
            return nil
        }
        guard png.count <= maxEmbedBytes else { return nil }
        return png.base64EncodedString()
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
                lines.append("\(n). [image]")
            }
        }
        if imageCount > 0 {
            lines.append("")
            lines.append("(images can't be copied as text — open clip and cue to grab them)")
        }
        return lines.joined(separator: "\n")
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
