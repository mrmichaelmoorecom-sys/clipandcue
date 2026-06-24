import AppKit

extension ClipItem {
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
        switch kind {
        case .text, .richText:
            return NSItemProvider(object: (text ?? "") as NSString)
        case .image:
            if let data = imageData, let image = NSImage(data: data) {
                return NSItemProvider(object: image)
            }
            return NSItemProvider()
        case .files:
            if let path = filePaths?.first {
                return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
            }
            return NSItemProvider()
        }
    }
}
