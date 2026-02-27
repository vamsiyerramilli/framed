import AppKit
import ImageIO

/// Actor-isolated, NSCache-backed thumbnail loader.
///
/// All CGImageSource decoding runs on the actor's executor (background).
/// Concurrent requests for the same file path are coalesced via `inFlight` — prevents
/// duplicate decodes when a user fast-scrolls over the same cells.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, CGImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 150 * 1024 * 1024   // 150 MB
    }

    /// Returns a thumbnail CGImage for the file at `filePath`, loading on a background thread.
    /// `size` is in points; the loaded pixel size is `size * 2` for Retina display.
    func thumbnail(for filePath: String, size: CGFloat = 200) async -> CGImage? {
        let key = filePath as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let existing = inFlight[filePath] {
            return await existing.value
        }

        let loadTask = Task<CGImage?, Never> { [size] in
            loadThumbnail(filePath: filePath, size: size)
        }
        inFlight[filePath] = loadTask

        let result = await loadTask.value
        inFlight.removeValue(forKey: filePath)

        if let result {
            // Cost in bytes: width * height * 4 (RGBA) — approximated as (size*2)^2 * 4
            let sidePixels = Int(size * 2)
            cache.setObject(result, forKey: key, cost: sidePixels * sidePixels * 4)
        }
        return result
    }
}

/// Free function (nonisolated) — runs the CGImageSource work away from the actor's queue.
private func loadThumbnail(filePath: String, size: CGFloat) -> CGImage? {
    let url = URL(fileURLWithPath: filePath) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }

    let options: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: size * 2,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,   // apply EXIF orientation
        kCGImageSourceShouldCacheImmediately: false
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}
