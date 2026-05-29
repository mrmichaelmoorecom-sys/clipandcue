// Generates img/og-image.png (1200x630) for social sharing — styled to match
// the website hero (line-art logo_stacked mark + wordmark on a cream/rose wash).
// Run from repo root:  swift scripts/make_og.swift
import AppKit

let W = 1200, H = 630
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("no rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

// Light wash: a touch of rose at the top fading to cream (like the hero).
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(0xf6,0xe9,0xee).cgColor, rgb(0xff,0xfd,0xfc).cgColor] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// Stacked brand logo (clip mark + "clip and cue" wordmark) as vector.
if let logo = NSImage(contentsOfFile: "img/logo_stacked.svg") {
    let lw: CGFloat = 500
    let lh = lw * (logo.size.height / max(logo.size.width, 1)) // 500 * 360/552 ≈ 326
    logo.draw(in: CGRect(x: (CGFloat(W) - lw)/2, y: 250, width: lw, height: lh))
}

// Centred text (origin bottom-left; y is each line's baseline).
func line(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let s = NSAttributedString(string: text, attributes: attrs)
    s.draw(at: CGPoint(x: (CGFloat(W) - s.size().width)/2, y: y))
}

line("Copy now. Paste later.",
     font: .systemFont(ofSize: 34, weight: .medium), color: rgb(0x7d,0x4f,0x5c), y: 178)
line("Free macOS menu bar clipboard manager  ·  clipandcue.com",
     font: .systemFont(ofSize: 23, weight: .regular), color: rgb(0x8a,0x7d,0x82), y: 120)

NSGraphicsContext.current!.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "img/og-image.png"))
print("wrote img/og-image.png")
