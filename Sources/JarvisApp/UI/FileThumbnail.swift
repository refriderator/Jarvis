import AppKit
import QuickLookThumbnailing
import SwiftUI

/// A file as Finder's icon view draws it: the picture itself for images, PDFs and videos (Quick Look), and its
/// type's icon while that's being made or when there's none (folders, most documents).
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    let thumbnails: ThumbnailCache
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: url) { image = await thumbnails.image(for: url, size: size) }
    }
}

/// Thumbnails already made, so scrolling back (the grid drops tiles that scroll away) doesn't make them again.
/// Keyed by the file's path and when it last changed, so an edited picture is drawn again.
@MainActor
final class ThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()
    /// Files Quick Look has no picture for: they keep their icon without asking again.
    private var none: Set<String> = []

    init() {
        cache.countLimit = 400
    }

    func image(for url: URL, size: CGFloat) async -> NSImage? {
        let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path)|\(changed?.timeIntervalSince1970 ?? 0)|\(size)"
        if let image = cache.object(forKey: key as NSString) { return image }
        guard !none.contains(key) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale,
                                                   representationTypes: .thumbnail)
        // Made off the main thread; only the finished picture (a CGImage, safe to pass between threads) comes back.
        let picture: CGImage? = await withCheckedContinuation { done in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                done.resume(returning: thumbnail?.cgImage)
            }
        }
        guard let picture else {
            none.insert(key)
            return nil
        }
        let image = NSImage(cgImage: picture, size: NSSize(width: CGFloat(picture.width) / scale,
                                                           height: CGFloat(picture.height) / scale))
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
