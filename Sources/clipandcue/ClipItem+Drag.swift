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
            registerClipID(on: provider)
            return provider
        }

        // Fallback path: per-kind manual registration for legacy clips
        // that don't have a snapshot (pre-v0.2.6 history, CloudKit-pulled
        // items, files clips).
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

        registerClipID(on: provider)
        return provider
    }

    /// Register the in-app grouping marker LAST on the provider. Apps that
    /// walk the type list in registration order (Slack, Claude, clipandnote,
    /// Notes, chat clients) used to see clip-id first and either fail to
    /// accept the drop or treat it as a 36-byte file attachment. Our own
    /// dropdown reads `registeredTypeIdentifiers` for the UTI so its order
    /// doesn't affect drop-to-group — only what other apps see.
    private func registerClipID(on provider: NSItemProvider) {
        let idData = id.uuidString.data(using: .utf8) ?? Data()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.clipIDUTI,
            visibility: .ownProcess
        ) { completion in
            completion(idData, nil)
            return nil
        }
    }
}
