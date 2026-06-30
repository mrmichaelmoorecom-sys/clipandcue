import AppKit

extension ClipItem {
    /// Private UTI registered on every drag so the dropdown's own `.onDrop`
    /// handlers can spot cross-row drags and convert them into groupings
    /// instead of treating them like external drags.
    static let clipIDUTI = "com.clipandcue.clip-id"

    /// Sort pasteboard types so drop targets pick the highest-fidelity rep
    /// they understand. App-native private types win, then vector (PDF /
    /// SVG / RTF), then raster, then text.
    static func sortedDragTypes<S: Sequence>(_ types: S) -> [String] where S.Element == String {
        // Match in this order; everything that doesn't match a predicate
        // falls into the final catch-all bucket.
        let rules: [(String) -> Bool] = [
            { $0.hasPrefix("com.apple.iWork.") },
            { $0.hasPrefix("com.apple.iWork-pb.") },
            { $0.hasPrefix("com.adobe.illustrator.") },
            { $0.hasPrefix("com.adobe.indesign.") },
            { $0.hasPrefix("com.adobe.photoshop") },
            { $0.hasPrefix("com.microsoft.") },
            { $0.hasPrefix("com.bohemiancoding.sketch.") },
            { $0.hasPrefix("com.serif.affinity.") },
            { $0 == "com.adobe.pdf" },
            { $0 == "public.svg-image" },
            { $0 == "public.rtf" },
            { $0 == "public.png" },
            { $0 == "public.tiff" },
            { $0 == "public.jpeg" },
            { $0 == "public.heic" || $0 == "public.heif" },
            { $0 == "public.utf8-plain-text" || $0 == "public.text" },
            { _ in true }
        ]
        var remaining = Set(types)
        var ordered: [String] = []
        for predicate in rules {
            let matched = remaining.filter(predicate).sorted()
            ordered.append(contentsOf: matched)
            remaining.subtract(matched)
        }
        return ordered
    }

    /// `NSItemProvider` for SwiftUI's `.onDrag` — carries the richest
    /// representation of this clip that the destination app will accept.
    ///
    /// - Text / rich text → `NSString` (UTF-8 plain text). RTF formatting
    ///   isn't preserved on drag (`NSItemProvider(object:)` only writes one
    ///   primary type); for full formatting use the normal copy/paste path.
    /// - Image → `NSImage`, which Cocoa auto-converts to PNG/TIFF/PDF for
    ///   whichever the drop target requests.
    /// - Files → the first file URL. SwiftUI's `.onDrag` returns a single
    ///   provider, so multi-file drags aren't supported in the MVP.
    func dragProvider() -> NSItemProvider {
        let provider = NSItemProvider()

        // Clip-id first so it's the most prominent registered type. The
        // dropdown's `.onDrop(of: [clipIDUTI])` keys off this; any drop
        // without it is treated as an external drop (and ignored by us).
        let idData = id.uuidString.data(using: .utf8) ?? Data()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.clipIDUTI,
            visibility: .ownProcess
        ) { completion in
            completion(idData, nil)
            return nil
        }

        // High-fidelity drag-out: when the clip carries a full pasteboard
        // snapshot (text / image / richText captured under v0.2.6+),
        // register *every* captured type on the provider so dragging back
        // into the source app round-trips editable — Keynote's
        // `com.apple.iWork.TSPNativeObject`, Illustrator's
        // `com.adobe.illustrator.aip`, Word's OOXML, etc.
        //
        // Registration *order* matters: macOS drop handlers (Keynote in
        // particular) tend to pick the first type they recognize, so we
        // register native/private app types first, then PDF/SVG vector,
        // then raster fallbacks. Drop into Keynote → it sees its native
        // type first and pastes editable. Drop into Photoshop → it skips
        // unfamiliar types and lands on PDF/PNG.
        if let snap = pasteboardSnapshot, !snap.isEmpty {
            for typeID in Self.sortedDragTypes(snap.keys) {
                guard let data = snap[typeID] else { continue }
                provider.registerDataRepresentation(
                    forTypeIdentifier: typeID,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }

            // Electron-based receivers (Slack, Claude, clipandnote, Discord, etc.)
            // bridge drops via Chromium's DataTransfer.files API which only
            // consumes drag operations whose payload includes a real file on
            // disk. Raw data and NSImage object registrations alone make the
            // receiver show the drop indicator (the MIME type is recognized)
            // and then silently drop on release (its file list is empty).
            // Register the rasterized image both as an NSImage object (for
            // receivers that load by class) and as a real file-URL object
            // (for Chromium's File API path).
            if let imgData = snap["public.png"] ?? snap["public.tiff"] ?? snap["public.jpeg"] ?? snap["com.adobe.pdf"],
               let img = NSImage(data: imgData) {
                provider.registerObject(img, visibility: .all)
                if let url = Self.writeDragTempImage(imgData, fallbackImage: img, clipID: id) {
                    provider.registerObject(url as NSURL, visibility: .all)
                }
            }

            return provider
        }

        // Fallback path: per-kind manual registration for legacy clips
        // that don't have a snapshot (pre-v0.2.6 history, CloudKit-pulled
        // items, files clips). Same per-type registration shape so the
        // clip-id stays on equal footing.
        switch kind {
        case .text, .richText:
            if let str = text, !str.isEmpty,
               let strData = str.data(using: .utf8) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: "public.utf8-plain-text",
                    visibility: .all
                ) { completion in
                    completion(strData, nil)
                    return nil
                }
            }
        case .image:
            if let data = imageData {
                let utType = imageUTType ?? "public.png"
                provider.registerDataRepresentation(
                    forTypeIdentifier: utType,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
                // TIFF fallback so apps that only accept TIFF (older image
                // editors, Notes) still receive the image.
                if !utType.contains("tiff"),
                   let img = NSImage(data: data),
                   let tiff = img.tiffRepresentation {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: "public.tiff",
                        visibility: .all
                    ) { completion in
                        completion(tiff, nil)
                        return nil
                    }
                }
                // NSImage object + file-URL registration for Electron-based
                // receivers (see snapshot-path comment above).
                if let img = NSImage(data: data) {
                    provider.registerObject(img, visibility: .all)
                    if let url = Self.writeDragTempImage(data, fallbackImage: img, clipID: id) {
                        provider.registerObject(url as NSURL, visibility: .all)
                    }
                }
            }
        case .files:
            if let path = filePaths?.first {
                let url = URL(fileURLWithPath: path)
                provider.registerObject(url as NSURL, visibility: .all)
            }
        case .group:
            // No primary rep — clip-id alone is enough for in-app grouping.
            // Drag-out from a collapsed group lands as nothing in the
            // destination; users can expand and drag individual children.
            break
        }

        return provider
    }

    /// Write the image bytes to a temp file Chromium-based receivers can
    /// pick up as a real File on disk. Prefers writing the original bytes
    /// when they're already PNG/JPEG; otherwise re-encodes the NSImage to
    /// PNG so the file has a content type Slack/Claude/clipandnote etc.
    /// understand. Name is keyed off the clip UUID so repeat drags of the
    /// same clip overwrite the same file (no /tmp pileup); macOS clears the
    /// temp dir at reboot.
    private static func writeDragTempImage(_ rawData: Data,
                                           fallbackImage: NSImage,
                                           clipID: UUID) -> URL? {
        let shortID = String(clipID.uuidString.prefix(8))

        // Direct write if the bytes are already in a web-loadable format.
        let head4 = rawData.prefix(4)
        let isPNG = head4 == Data([0x89, 0x50, 0x4E, 0x47])
        let isJPEG = head4.prefix(3) == Data([0xFF, 0xD8, 0xFF])
        if isPNG || isJPEG {
            let ext = isPNG ? "png" : "jpg"
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("clipandcue-\(shortID).\(ext)")
            return (try? rawData.write(to: url)) != nil ? url : nil
        }

        // Re-encode TIFF / PDF / anything else through NSBitmapImageRep → PNG.
        guard let tiff = fallbackImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipandcue-\(shortID).png")
        return (try? png.write(to: url)) != nil ? url : nil
    }
}
