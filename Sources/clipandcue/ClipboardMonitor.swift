import AppKit

/// Polls the general pasteboard and feeds new copies into the store.
final class ClipboardMonitor {
    /// Fired when a copy was skipped because it exceeded the size cap.
    var onOversized: ((_ bytes: Int, _ kindLabel: String) -> Void)?

    private let store: ClipStore
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        switch readPasteboard() {
        case .none:
            break
        case .item(let item):
            store.add(item)
        case .oversize(let bytes, let label):
            onOversized?(bytes, label)
        }
    }

    private enum ReadResult {
        case none
        case item(ClipItem)
        case oversize(bytes: Int, kindLabel: String)
    }

    private func readPasteboard() -> ReadResult {
        let cap = AppSettings.shared.sizeCapBytes

        // 1. Files copied from Finder (stored as path references — tiny).
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map { $0.path }
            return .item(ClipItem(kind: .files, filePaths: paths))
        }

        // 2. Image data (screenshots, copied image regions).
        if let (data, utType) = bestImageData() {
            if data.count > cap {
                return .oversize(bytes: data.count, kindLabel: "image")
            }
            let image = NSImage(data: data)
            let thumb = image.flatMap { ImageUtils.thumbnailPNG(from: $0, maxDimension: 96) }
            return .item(ClipItem(
                kind: .image,
                imageData: data,
                imageUTType: utType,
                thumbnailData: thumb,
                pixelWidth: image.flatMap { ImageUtils.pixelSize($0)?.width },
                pixelHeight: image.flatMap { ImageUtils.pixelSize($0)?.height }))
        }

        // 3. Rich text (keep the RTF for fidelity, plus a plain-text preview).
        if let rtf = pasteboard.data(forType: .rtf) {
            if rtf.count > cap {
                return .oversize(bytes: rtf.count, kindLabel: "rich text")
            }
            let plain = pasteboard.string(forType: .string)
                ?? NSAttributedString(rtf: rtf, documentAttributes: nil)?.string
                ?? ""
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
            return .item(ClipItem(kind: .richText, text: plain, rtfData: rtf))
        }

        // 4. Plain text.
        if let str = pasteboard.string(forType: .string) {
            guard !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
            if str.utf8.count > cap {
                return .oversize(bytes: str.utf8.count, kindLabel: "text")
            }
            return .item(ClipItem(kind: .text, text: str))
        }

        return .none
    }

    /// Prefer PNG, fall back to TIFF.
    private func bestImageData() -> (Data, String)? {
        if let png = pasteboard.data(forType: .png) {
            return (png, "public.png")
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return (tiff, "public.tiff")
        }
        return nil
    }
}
