import AppKit

/// Collects the whole history into a single new note in the Notes app.
/// Text/rich-text becomes text; files/folders become their names (one per line);
/// images are skipped (a text note can't hold them cleanly).
///
/// Runs the AppleScript in-process via NSAppleScript so the Automation
/// permission is attributed to clip and cue itself (paired with
/// NSAppleEventsUsageDescription in Info.plist). If Notes can't be reached,
/// it falls back to copying the list to the clipboard.
enum NoteExporter {
    static func exportToNewNote(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }

        let escaped = buildHTML(items)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let source = """
        tell application "Notes"
            activate
            make new note with properties {body:"\(escaped)"}
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            NSLog("clipandcue: New note failed (\(errorInfo[NSAppleScript.errorNumber] ?? "?")): "
                  + "\(errorInfo[NSAppleScript.errorMessage] ?? "")")
            fallbackToClipboard(items)
        }
    }

    /// If Notes is unreachable (e.g. Automation permission denied), put the list
    /// on the clipboard so the action still does something useful.
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

        var imagesSkipped = 0
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
                imagesSkipped += 1
            }
        }

        var html = "<div><b>clip and cue — \(items.count) item\(items.count == 1 ? "" : "s")</b></div>"
        html += "<div>\(esc(df.string(from: Date())))</div><div><br></div>"
        html += rows.joined(separator: "<div><br></div>")
        if imagesSkipped > 0 {
            let s = imagesSkipped == 1 ? "" : "s"
            html += "<div><br></div><div><i>(\(imagesSkipped) image\(s) not included)</i></div>"
        }
        return html
    }

    private static func buildPlainText(_ items: [ClipItem]) -> String {
        var imagesSkipped = 0
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
                imagesSkipped += 1
            }
        }
        if imagesSkipped > 0 {
            lines.append("")
            lines.append("(\(imagesSkipped) image\(imagesSkipped == 1 ? "" : "s") not included)")
        }
        return lines.joined(separator: "\n")
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
