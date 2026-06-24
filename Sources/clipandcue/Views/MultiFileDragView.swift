import SwiftUI
import AppKit

/// AppKit-backed drag source for multi-file clips. SwiftUI's `.onDrag` is
/// single-item: a row with N files can only carry one URL in its
/// `NSItemProvider`, so a drop into Finder only copies the first file and a
/// drop into Photoshop / Mail only opens the first. A real multi-file drag
/// uses `NSDraggingSession` with one `NSDraggingItem` per file, which is
/// what the system itself does when you drag a multi-selection out of
/// Finder.
///
/// Sitting on top of the SwiftUI row also means we have to intercept the
/// click — once an AppKit view is in front, SwiftUI's tap gesture stops
/// receiving mouseDown — so the overlay forwards a no-drag click back
/// through `onTap` to fire the existing paste-all path.
struct MultiFileDragSurface: NSViewRepresentable {
    let paths: [String]
    let onTap: () -> Void

    func makeNSView(context: Context) -> MultiDragNSView {
        MultiDragNSView()
    }

    func updateNSView(_ nsView: MultiDragNSView, context: Context) {
        nsView.paths = paths
        nsView.onTap = onTap
    }
}

final class MultiDragNSView: NSView, NSDraggingSource {
    var paths: [String] = []
    var onTap: (() -> Void)?

    /// Mouse-down location in window coords; nil between drag-start and the
    /// next press. Used to decide tap vs. drag.
    private var pressOrigin: NSPoint?
    private let dragThreshold: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin else { return }
        let dx = event.locationInWindow.x - origin.x
        let dy = event.locationInWindow.y - origin.y
        guard hypot(dx, dy) > dragThreshold else { return }
        pressOrigin = nil
        beginMultiFileDrag(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = (pressOrigin != nil)
        pressOrigin = nil
        if wasPressed { onTap?() }
    }

    private func beginMultiFileDrag(event: NSEvent) {
        let items: [NSDraggingItem] = paths.enumerated().map { (i, path) in
            let url = URL(fileURLWithPath: path) as NSURL
            let item = NSDraggingItem(pasteboardWriter: url)
            // Stagger preview frames so the cursor carries a visible "stack"
            // of all N files during the drag (Finder does the same).
            let offset = CGFloat(i) * 4
            item.draggingFrame = NSRect(
                x: offset, y: -offset,
                width: bounds.width, height: bounds.height)
            // Use each file's system icon as the per-item drag preview.
            let icon = NSWorkspace.shared.icon(forFile: path)
            let side = max(20, min(40, bounds.height - 8))
            icon.size = NSSize(width: side, height: side)
            item.imageComponentsProvider = {
                let comp = NSDraggingImageComponent(key: .icon)
                comp.contents = icon
                comp.frame = NSRect(origin: .zero, size: icon.size)
                return [comp]
            }
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic, .link]
    }
}
