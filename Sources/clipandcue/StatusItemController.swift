import AppKit
import SwiftUI

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: ClipStore
    private var warningTimer: Timer?

    var onPick: ((Int) -> Void)?
    var onPreferences: (() -> Void)?
    var onHowTo: (() -> Void)?
    var onExport: (() -> Void)?

    init(store: ClipStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configurePopover()
    }

    // MARK: Icon

    private func normalIcon() -> NSImage? {
        // Cowork's branded template ships menubarTemplate.png + @2x; NSImage(named:)
        // loads both reps and picks the right one per display.
        if let src = loadResourcePNG("menubarTemplate@2x")
            ?? loadResourcePNG("menubarTemplate")
            ?? NSImage(named: "menubarTemplate") {
            return crispTemplate(from: src, height: 12)
        }
        let img = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "clipandcue")
        img?.isTemplate = true
        return img
    }

    /// Re-render the mark at exact device pixels with interpolation off, so the
    /// menu bar draws it 1:1 (crisp) instead of smooth-scaling the source.
    private func crispTemplate(from src: NSImage, height h: CGFloat) -> NSImage {
        let aspect = src.size.height > 0 ? src.size.width / src.size.height : 1
        let pt = NSSize(width: (h * aspect).rounded(), height: h)
        let scale: CGFloat = 2 // render for Retina; @1x displays downscale cleanly
        let pxW = Int((pt.width * scale).rounded())
        let pxH = Int((pt.height * scale).rounded())
        guard pxW > 0, pxH > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            src.isTemplate = true
            src.size = pt
            return src
        }
        rep.size = pt
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .none
            ctx.cgContext.interpolationQuality = .none
            src.draw(in: NSRect(origin: .zero, size: pt))
        }
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: pt)
        out.addRepresentation(rep)
        out.isTemplate = true
        return out
    }

    private func loadResourcePNG(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover(_:))
        button.target = self
        if let base = normalIcon() {
            let pink = NSColor(srgbRed: 213/255, green: 193/255, blue: 198/255, alpha: 1.0)  // #d5c1c6
            button.image = tinted(image: base, with: pink)
        } else {
            button.image = nil
        }
    }

    /// Bake `color` into a copy of `image` (sourceAtop), and mark it
    /// non-template so macOS doesn't override the color in the menu bar.
    private func tinted(image src: NSImage, with color: NSColor) -> NSImage {
        let size = src.size
        let out = NSImage(size: size)
        out.lockFocus()
        src.draw(at: .zero, from: NSRect(origin: .zero, size: size),
                 operation: .sourceOver, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let root = MenuListView(
            store: store,
            onPick: { [weak self] idx in self?.handlePick(idx) },
            onClear: { [weak self] in self?.store.clear() },
            onExport: { [weak self] in
                self?.closePopover()
                self?.onExport?()
            },
            onPreferences: { [weak self] in
                self?.closePopover()
                self?.onPreferences?()
            },
            onHowTo: { [weak self] in
                self?.closePopover()
                self?.onHowTo?()
            },
            onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
            return
        }
        Paster.shared.rememberFrontmostApp()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() { popover.performClose(nil) }

    private func handlePick(_ index: Int) {
        closePopover()
        onPick?(index)
    }

    // MARK: Not-saved warning

    func flashWarning() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
        let warn = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                           accessibilityDescription: "Copy not saved")?
            .withSymbolConfiguration(config)
        warn?.isTemplate = false
        button.image = warn
        warningTimer?.invalidate()
        warningTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.statusItem.button?.image = self?.normalIcon()
        }
    }
}
