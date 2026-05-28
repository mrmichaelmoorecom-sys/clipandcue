import AppKit

enum ImageUtils {
    /// Pixel dimensions of the largest representation.
    static func pixelSize(_ image: NSImage) -> (width: Int, height: Int)? {
        var w = 0, h = 0
        for rep in image.representations {
            w = max(w, rep.pixelsWide)
            h = max(h, rep.pixelsHigh)
        }
        if w > 0 && h > 0 { return (w, h) }
        let s = image.size
        guard s.width > 0, s.height > 0 else { return nil }
        return (Int(s.width), Int(s.height))
    }

    /// Downscaled PNG preview, longest edge bounded by `maxDimension`.
    static func thumbnailPNG(from image: NSImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = NSSize(width: max(1, floor(size.width * scale)),
                            height: max(1, floor(size.height * scale)))

        let thumb = NSImage(size: target)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero, operation: .copy, fraction: 1.0)
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
