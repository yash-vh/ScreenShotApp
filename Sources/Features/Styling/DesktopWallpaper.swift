import AppKit
import ImageIO

/// The current desktop picture, used by the "Desktop" presentation backdrop.
/// Decoded once per wallpaper file and downsampled, since the live canvas redraws it every frame.
public enum DesktopWallpaper {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: (url: URL, image: CGImage)?

    /// Longest edge of the cached image; plenty for a padded backdrop
    static let maxPixelSize = 2560

    public static func current() -> CGImage? {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cache, cache.url == url { return cache.image }
        guard let image = load(url) else { return nil }
        cache = (url, image)
        return image
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Draws `image` scaled to fill `rect` (cropping the overflow), in a y-up or flipped (y-down) context
    public static func drawAspectFill(_ image: CGImage, in context: CGContext, rect: CGRect, flipped: Bool) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2, width: drawSize.width, height: drawSize.height)

        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .high
        if flipped {
            context.translateBy(x: 0, y: drawRect.maxY + drawRect.minY)
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: drawRect)
        context.restoreGState()
    }
}
