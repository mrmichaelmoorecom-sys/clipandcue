// Generates the DMG background (gray + arrow + headline in Outfit).
// Usage:  swift scripts/make_dmg_bg.swift <outPath.png> <scale>
import AppKit
import CoreText

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "/tmp/dmgbg.png"
let scale = CGFloat(args.count > 2 ? (Double(args[2]) ?? 2) : 2)

let LW: CGFloat = 660, LH: CGFloat = 400          // logical (point) size
let W = Int(LW * scale), H = Int(LH * scale)

// Register the Outfit variable font.
let fontURL = URL(fileURLWithPath: "scripts/fonts/Outfit.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

func outfit(_ size: CGFloat, weight: Int = 800) -> NSFont {
    let variation: [NSNumber: NSNumber] = [NSNumber(value: 0x77676874): NSNumber(value: weight)] // 'wght'
    let attrs: [CFString: Any] = [
        kCTFontFamilyNameAttribute: "Outfit" as CFString,
        kCTFontVariationAttribute: variation as CFDictionary
    ]
    let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
    return CTFontCreateWithFontDescriptor(desc, size, nil) as NSFont
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError() }

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
gctx.cgContext.scaleBy(x: scale, y: scale)        // draw in logical coords
gctx.shouldAntialias = true

// Background
rgb(0xec, 0xec, 0xec).setFill()
NSRect(x: 0, y: 0, width: LW, height: LH).fill()

// Arrow (centred between the icon slots; origin is bottom-left, so y=200 ≈ icon row)
let arrow = NSBezierPath()
arrow.lineWidth = 11
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: CGPoint(x: 283, y: 200)); arrow.line(to: CGPoint(x: 377, y: 200))
arrow.move(to: CGPoint(x: 377, y: 200)); arrow.line(to: CGPoint(x: 350, y: 173))
arrow.move(to: CGPoint(x: 377, y: 200)); arrow.line(to: CGPoint(x: 350, y: 227))
rgb(0x6b, 0x6b, 0x70).setStroke()
arrow.stroke()

// Headline — auto-fit to ~600pt wide, near the top.
let text = "You're amazing... And productive."
var size: CGFloat = 40
let w40 = NSAttributedString(string: text, attributes: [.font: outfit(40)]).size().width
if w40 > 600 { size = 40 * 600 / w40 }

let para = NSMutableParagraphStyle(); para.alignment = .center
let glow = NSShadow(); glow.shadowColor = NSColor.white.withAlphaComponent(0.75)
glow.shadowBlurRadius = 5; glow.shadowOffset = .zero
let attrs: [NSAttributedString.Key: Any] = [
    .font: outfit(size), .foregroundColor: rgb(0x2e, 0x2a, 0x2b),
    .paragraphStyle: para, .shadow: glow
]
let astr = NSAttributedString(string: text, attributes: attrs)
let ts = astr.size()
astr.draw(at: CGPoint(x: (LW - ts.width)/2, y: LH - 36 - ts.height))

gctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
FileHandle.standardError.write("font: \(outfit(size).familyName ?? "?")  headlineSize: \(size)\n".data(using: .utf8)!)
print("wrote \(outPath)")
