import SwiftUI
import AppKit

/// One row inside an expanded multi-file clip. Shows a real preview when the
/// path points at an image / PDF (loaded off the main thread, capped by file
/// size), with the system file icon as fallback for non-image types.
///
/// - Tap → paste just this file via the parent's `onPick`.
/// - Press + drag → drops the file URL into any other app (Finder, Mail,
///   image editors, web upload fields, etc.).
struct FileSubRowView: View {
    let path: String
    /// Use the larger 36px thumbnail in the HUD; the dropdown defaults to 18px.
    var large: Bool = false
    var onPick: () -> Void

    @State private var preview: NSImage?
    @State private var hovered = false

    private var side: CGFloat { large ? 36 : 18 }
    private var url: URL { URL(fileURLWithPath: path) }
    private var name: String { (path as NSString).lastPathComponent }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: side, height: side)

            Text(name)
                .font(large ? .callout : .caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary.opacity(0.88))
            Spacer(minLength: 0)
        }
        .padding(.leading, large ? 64 : 44)
        .padding(.trailing, 12)
        .padding(.vertical, large ? 6 : 4)
        .background(hovered ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onPick)
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onAppear(perform: loadPreview)
        .help("Paste \(name)")
    }

    private func loadPreview() {
        guard preview == nil else { return }
        let p = path
        let target: CGFloat = large ? 72 : 36
        DispatchQueue.global(qos: .userInitiated).async {
            let cap = 50 * 1024 * 1024
            guard let size = try? FileManager.default
                    .attributesOfItem(atPath: p)[.size] as? Int,
                  size <= cap,
                  let image = NSImage(contentsOfFile: p),
                  let data = ImageUtils.thumbnailPNG(from: image, maxDimension: target * 2),
                  let thumb = NSImage(data: data)
            else { return }
            DispatchQueue.main.async { self.preview = thumb }
        }
    }
}
