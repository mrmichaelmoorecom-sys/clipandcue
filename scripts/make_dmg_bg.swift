// Generates the DMG background (pale-pink wash + faint clip watermark + arrow
// + headline in Outfit). Usage:  swift scripts/make_dmg_bg.swift <outPath.png> <scale>
import AppKit
import CoreText

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "/tmp/dmgbg.png"
let scale = CGFloat(args.count > 2 ? (Double(args[2]) ?? 2) : 2)

let LW: CGFloat = 660, LH: CGFloat = 400
let W = Int(LW * scale), H = Int(LH * scale)

CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "scripts/fonts/Outfit.ttf") as CFURL, .process, nil)

func outfit(_ size: CGFloat, weight: Int = 800) -> NSFont {
    let variation: [NSNumber: NSNumber] = [NSNumber(value: 0x77676874): NSNumber(value: weight)]
    let attrs: [CFString: Any] = [
        kCTFontFamilyNameAttribute: "Outfit" as CFString,
        kCTFontVariationAttribute: variation as CFDictionary
    ]
    return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attrs as CFDictionary), size, nil) as NSFont
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

// Single clip-mark SVG (matches the site's mark), written to temp for NSImage.
let clipSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M16.5 6v11.5c0 2.21-1.79 4-4 4s-4-1.79-4-4V5c0-1.38 1.12-2.5 2.5-2.5s2.5 1.12 2.5 2.5v10.5c0 .55-.45 1-1 1s-1-.45-1-1V6H10v9.5c0 1.38 1.12 2.5 2.5 2.5s2.5-1.12 2.5-2.5V5c0-2.21-1.79-4-4-4S7 2.79 7 5v12.5c0 3.04 2.46 5.5 5.5 5.5s5.5-2.46 5.5-5.5V6h-1.5z" fill="#b58592"/></svg>
"""
let clipURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ccclip.svg")
try? clipSVG.write(to: clipURL, atomically: true, encoding: .utf8)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError() }

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext
cg.scaleBy(x: scale, y: scale)

// Pale-pink diagonal wash.
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(0xfd,0xf6,0xf8).cgColor, rgb(0xf6,0xe8,0xed).cgColor, rgb(0xfb,0xf0,0xf4).cgColor] as CFArray,
    locations: [0, 0.55, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: LH), end: CGPoint(x: LW, y: 0),
                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Faint clip watermark, large, tilted, lower-right.
if let mark = NSImage(contentsOf: clipURL) {
    NSGraphicsContext.saveGraphicsState()
    cg.translateBy(x: 510, y: 150)
    cg.rotate(by: -16 * .pi / 180)
    let s: CGFloat = 300
    mark.draw(in: CGRect(x: -s/2, y: -s/2, width: s, height: s),
              from: .zero, operation: .sourceOver, fraction: 0.07)
    NSGraphicsContext.restoreGraphicsState()
}

// Arrow (centred on the icon row).
let arrow = NSBezierPath()
arrow.lineWidth = 11; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: CGPoint(x: 283, y: 200)); arrow.line(to: CGPoint(x: 377, y: 200))
arrow.move(to: CGPoint(x: 377, y: 200)); arrow.line(to: CGPoint(x: 350, y: 173))
arrow.move(to: CGPoint(x: 377, y: 200)); arrow.line(to: CGPoint(x: 350, y: 227))
rgb(0x2e, 0x2a, 0x2b).setStroke()   // black (matches the headline ink)
arrow.stroke()

// Headline — auto-fit to ~600pt wide, near the top.
let text = "You're amazing... And productive."
var size: CGFloat = 40
let w40 = NSAttributedString(string: text, attributes: [.font: outfit(40)]).size().width
if w40 > 600 { size = 40 * 600 / w40 }
let para = NSMutableParagraphStyle(); para.alignment = .center
let glow = NSShadow(); glow.shadowColor = NSColor.white.withAlphaComponent(0.6)
glow.shadowBlurRadius = 5; glow.shadowOffset = .zero
let astr = NSAttributedString(string: text, attributes: [
    .font: outfit(size), .foregroundColor: rgb(0x2e,0x2a,0x2b), .paragraphStyle: para, .shadow: glow])
let ts = astr.size()
astr.draw(at: CGPoint(x: (LW - ts.width)/2, y: LH - 36 - ts.height))

gctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
