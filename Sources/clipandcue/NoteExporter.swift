import AppKit

/// Collects the whole history into a single new note in the Notes app.
/// Text/rich-text becomes text; files/folders become their names (one per line);
/// images are skipped (a text note can't hold them cleanly).
enum NoteExporter {
    static func exportToNewNote(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        let html = buildHTML(items)

        // Pass the body via a temp file so large histories don't hit ARG_MAX.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipandcue-note-\(UUID().uuidString).html")
        guard (try? html.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return }

        let script = """
        on run argv
          set p to item 1 of argv
          set fh to open for access (POSIX file p)
          set txt to (read fh as «class utf8»)
          close access fh
          tell application "Notes"
            activate
            make new note with properties {body:txt}
          end tell
        end run
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script, tmp.path]
        proc.terminationHandler = { _ in try? FileManager.default.removeItem(at: tmp) }
        do { try proc.run() } catch { try? FileManager.default.removeItem(at: tmp) }
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

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
