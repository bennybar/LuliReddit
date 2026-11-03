import CryptoKit
import ImageIO
import UIKit

/// The one image pipeline: memory cache → disk cache → network, with one
/// download per URL and one decode per URL+size however many views ask at once.
/// Files are kept as downloaded; every size is a thumbnail decoded from them off
/// the main thread, so a list never decodes a full-size photo for a small slot.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader(
        directory: URL.cachesDirectory.appending(path: "luli_cache/images"),
        // Settings → Image cache size. Read straight from the prefs and only once:
        // the loader is built once ("after restarting Ilay", as the setting says),
        // possibly before the settings store is up.
        diskLimit: Int64(UserDefaults.standard.object(forKey: "flutter.imageCacheMb") as? Int ?? 512) << 20,
        session: URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.urlCache = nil // The disk cache below is the cache.
            return config
        }())
    )

    /// Several callers wait on one task; it's cancelled when the last one leaves.
    private final class Flight<T> {
        var task: Task<T?, Never>!
        var waiters = 1
    }

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let diskLimit: Int64
    private let session: URLSession
    private let animationBudget: Int
    private let lock = NSLock()
    private var decodes: [String: Flight<UIImage>] = [:]
    private var downloads: [String: Flight<URL>] = [:]
    private var diskBytes: Int64 = 0

    /// `animationBudget`: the most bytes one animation's decoded frames may take
    /// (see `decodeFrames`).
    init(directory: URL, diskLimit: Int64, session: URLSession, animationBudget: Int = 40 << 20) {
        self.directory = directory
        self.diskLimit = diskLimit
        self.session = session
        self.animationBudget = animationBudget
        // A share of the device, capped: decoded feed images are what's kept here,
        // and NSCache also lets go by itself under memory pressure. 512 MB let a feed
        // of GIFs push the app towards a jetsam kill before NSCache reacted.
        memory.totalCostLimit = Int(min(ProcessInfo.processInfo.physicalMemory / 8, 192 << 20))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task.detached(priority: .utility) { self.trimDisk() }
    }

    /// Synchronous memory lookup, so a reused cell can paint without a placeholder frame.
    func cached(url: URL, maxPixelSize: Int, animated: Bool = false) -> UIImage? {
        memory.object(forKey: Self.key(url, maxPixelSize, animated) as NSString)
    }

    /// `url` decoded to fit `maxPixelSize` on its longest side (0: full size). The
    /// first frame unless `animated`; an animated result has `UIImage.images` set
    /// and needs a `UIImageView` (see `RemoteImage`). nil if it failed or was cancelled.
    func image(url: URL, maxPixelSize: Int, animated: Bool = false) async -> UIImage? {
        let key = Self.key(url, maxPixelSize, animated)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        return await join(key, \.decodes) { [self] in
            guard let file = await fileForImage(url), !Task.isCancelled else { return nil }
            let image = Self.decode(file, maxPixelSize: maxPixelSize, animated: animated, budget: animationBudget)
            guard !Task.isCancelled else { return nil }
            guard let image else {
                // Not an image after all (an error page served as 200): don't keep it.
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            return image
        }
    }

    /// Loads into the caches ahead of time, at low priority. Never cancelled by a
    /// view leaving; a view asking for the same image joins it (and raises its priority).
    func prefetch(urls: [URL], maxPixelSize: Int) {
        for url in urls where cached(url: url, maxPixelSize: maxPixelSize) == nil {
            Task.detached(priority: .utility) { _ = await self.image(url: url, maxPixelSize: maxPixelSize) }
        }
    }

    /// Settings → Clear cache. Files in use by a running decode are simply fetched again next time.
    func clearAll() {
        memory.removeAllObjects()
        lock.withLock { diskBytes = 0 }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func clearMemory() { memory.removeAllObjects() }

    // MARK: - Flights

    private func join<T>(
        _ key: String,
        _ table: ReferenceWritableKeyPath<ImageLoader, [String: Flight<T>]>,
        keepRunning: Bool = false,
        work: @escaping @Sendable () async -> T?
    ) async -> T? {
        let flight: Flight<T> = lock.withLock {
            if let running = self[keyPath: table][key] {
                running.waiters += 1
                return running
            }
            let new = Flight<T>()
            self[keyPath: table][key] = new
            // Set under the lock, before the task can get to removing its own entry.
            new.task = Task.detached(priority: Task.currentPriority) { [self] in
                let result = await work()
                lock.withLock {
                    if self[keyPath: table][key] === new { self[keyPath: table][key] = nil }
                }
                return result
            }
            return new
        }
        return await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: { [self] in
            if keepRunning { return }
            let last = lock.withLock {
                flight.waiters -= 1
                guard flight.waiters == 0 else { return false }
                // A new caller from here on starts afresh rather than joining a cancelled task.
                if self[keyPath: table][key] === flight { self[keyPath: table][key] = nil }
                return true
            }
            // Outside the lock: this runs the cancellation handler of the flight it
            // waits on (a decode's download) right here, and that takes the lock too.
            if last { flight.task.cancel() }
        }
    }

    // MARK: - Disk

    private func fileForImage(_ url: URL) async -> URL? {
        let file = directory.appending(path: Self.fileName(url))
        if FileManager.default.fileExists(atPath: file.path) {
            // The modification date is the last use: what the size limit evicts by.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return file
        }
        // A download always finishes, into the cache, even if nobody's waiting any more.
        // Cancelling threw away the progress whenever a card left the screen or was
        // refreshed (Home swaps its cards for full posts moments after showing them), so
        // a slow image kept starting over and might never appear.
        return await join(url.absoluteString, \.downloads, keepRunning: true) { [self] in
            guard let (temp, response) = try? await session.download(from: url) else { return nil }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: temp)
                return nil
            }
            let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: temp)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            let over = lock.withLock {
                diskBytes += Int64(size)
                return diskBytes > diskLimit
            }
            if over { trimDisk() }
            return file
        }
    }

    /// Down to 85% of the limit, least recently used first, so it isn't redone on every download.
    func trimDisk() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        var entries = files.compactMap { file -> (file: URL, size: Int64, used: Date)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        if total > diskLimit {
            entries.sort { $0.used < $1.used }
            for entry in entries where total > diskLimit * 85 / 100 {
                try? FileManager.default.removeItem(at: entry.file)
                total -= entry.size
            }
        }
        lock.withLock { diskBytes = total }
    }

    // MARK: - Decoding

    private static func key(_ url: URL, _ maxPixelSize: Int, _ animated: Bool) -> String {
        "\(maxPixelSize)|\(animated ? "a" : "s")|\(url.absoluteString)"
    }

    private static func fileName(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func cost(of image: UIImage) -> Int {
        // The frames repeated for timing are the same UIImage: count each once.
        Set(image.images ?? [image]).reduce(0) { $0 + ($1.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) }
    }

    private static func decode(_ file: URL, maxPixelSize: Int, animated: Bool, budget: Int) -> UIImage? {
        // ShouldCache false: the source itself keeps nothing; only the thumbnail lives on.
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, on this thread, rather than at first draw on the main one.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if maxPixelSize > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        let count = CGImageSourceGetCount(source)
        guard let first = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        if animated && count > 1 { return decodeFrames(source, count: count, first: first, options: options, budget: budget) }
        return UIImage(cgImage: first)
    }

    /// A long clip keeps its running time but drops frames beyond this: every frame
    /// stays decoded in memory while it plays.
    private static let maxFrames = 120

    /// Frames are also capped by `budget` bytes (frame 0's size times the count), so
    /// a big slot gets fewer frames; when not even two fit, it stays still on frame 0.
    private static func decodeFrames(_ source: CGImageSource, count: Int, first: CGImage, options: [CFString: Any], budget: Int) -> UIImage? {
        let allowed = min(maxFrames, budget / max(1, first.bytesPerRow * first.height))
        if allowed < 2 { return UIImage(cgImage: first) }
        let step = max(1, Int((Double(count) / Double(allowed)).rounded(.up)))
        var frames: [(image: UIImage, centis: Int)] = []
        for start in stride(from: 0, to: count, by: step) {
            if Task.isCancelled { return nil }
            guard let cg = start == 0 ? first : CGImageSourceCreateThumbnailAtIndex(source, start, options as CFDictionary) else { continue }
            var delay = 0.0
            for index in start..<min(start + step, count) { delay += frameDelay(source, index) }
            frames.append((UIImage(cgImage: cg), max(1, Int((delay * 100).rounded()))))
        }
        guard !frames.isEmpty else { return nil }
        // UIImage plays every frame for the same time: a frame's delay becomes a
        // number of repeats of the shortest step they all fit (the same UIImage, no extra memory).
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let unit = frames.reduce(0) { gcd($0, $1.centis) }
        let sequence = frames.flatMap { Array(repeating: $0.image, count: $0.centis / unit) }
        return UIImage.animatedImage(with: sequence, duration: Double(frames.reduce(0) { $0 + $1.centis }) / 100)
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let formats: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        ]
        for (dictionary, unclamped, clamped) in formats {
            guard let values = properties[dictionary] as? [CFString: Any] else { continue }
            let delay = values[unclamped] as? Double ?? values[clamped] as? Double ?? 0
            // Browsers play "as fast as possible" frames at 10fps; so do we.
            return delay < 0.02 ? 0.1 : delay
        }
        return 0.1
    }
}
