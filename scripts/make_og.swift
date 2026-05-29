// Generates img/og-image.png (1200x630) for social sharing.
// Run from repo root:  swift scripts/make_og.swift
import AppKit

let W = 1200, H = 630
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("no rep")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

// Rose-tint vertical gradient
let space = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: space,
    colors: [rgb(0xfb,0xf3,0xf5).cgColor, rgb(0xf0,0xd6,0xdd).cgColor] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// App icon, centred in the upper area
if let icon = NSImage(contentsOfFile: "img/appicon_1024.png") {
    let s: CGFloat = 220
    icon.draw(in: CGRect(x: (CGFloat(W) - s)/2, y: 360, width: s, height: s))
}

// Centred text lines (origin is bottom-left; y is each line's baseline-bottom)
func line(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = NSAttributedString(string: text, attributes: attrs)
    s.draw(at: CGPoint(x: (CGFloat(W) - s.size().width)/2, y: y))
}

line("clip and cue", font: .boldSystemFont(ofSize: 82), color: rgb(0x2e,0x2a,0x2b), y: 250)
line("Your last 9 copies, one keystroke away", font: .systemFont(ofSize: 33), color: rgb(0x7d,0x4f,0x5c), y: 200)
line("Free macOS menu bar clipboard manager  ·  clipandcue.com",
     font: .systemFont(ofSize: 23, weight: .medium), color: rgb(0x6a,0x5f,0x63), y: 150)

NSGraphicsContext.current!.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: "img/og-image.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
