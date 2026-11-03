import UIKit
import XCTest
@testable import Ilay

/// Serves a generated image and counts requests; no network.
private final class ImageStubProtocol: URLProtocol {
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var cancelled = 0
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var stopped = false

    override func startLoading() {
        Self.lock.withLock { Self.requests += 1 }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            guard !stopped else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopped = true
        Self.lock.withLock { Self.cancelled += 1 }
    }
}

final class ImageLoaderTests: XCTestCase {
    private var directory: URL!
    private let url = URL(string: "https://i.redd.it/test.png")!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        ImageStubProtocol.requests = 0
        ImageStubProtocol.cancelled = 0
        ImageStubProtocol.delay = 0
        ImageStubProtocol.status = 200
        ImageStubProtocol.body = png(width: 800, height: 400)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func loader(diskLimit: Int64 = 1 << 30, animationBudget: Int = 40 << 20) -> ImageLoader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageStubProtocol.self]
        return ImageLoader(directory: directory, diskLimit: diskLimit, session: URLSession(configuration: config), animationBudget: animationBudget)
    }

    private var files: [URL] { (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] }

    func testDownsamplesToTheLongestSide() async throws {
        let loaded = await loader().image(url: url, maxPixelSize: 100)
        let image = try XCTUnwrap(loaded)
        XCTAssertEqual(image.size.width, 100)
        XCTAssertEqual(image.size.height, 50)
    }

    func testDoesNotUpscaleASmallImage() async throws {
        let loaded = await loader().image(url: url, maxPixelSize: 4000)
        let image = try XCTUnwrap(loaded)
        XCTAssertEqual(image.size.width, 800)
    }

    func testMemoryCacheIsPerSizeAndSkipsTheNetwork() async throws {
        let loader = loader()
        XCTAssertNil(loader.cached(url: url, maxPixelSize: 100))
        let first = await loader.image(url: url, maxPixelSize: 100)
        let second = await loader.image(url: url, maxPixelSize: 100)
        XCTAssertTrue(first === second)
        XCTAssertTrue(loader.cached(url: url, maxPixelSize: 100) === first)
        XCTAssertNil(loader.cached(url: url, maxPixelSize: 200))
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testDiskCacheServesAnotherSizeAndANewLoader() async throws {
        let first = loader()
        _ = await first.image(url: url, maxPixelSize: 100)
        let otherSize = await first.image(url: url, maxPixelSize: 200)
        XCTAssertEqual(otherSize?.size.width, 200)
        let restarted = await loader().image(url: url, maxPixelSize: 300)
        XCTAssertEqual(restarted?.size.width, 300)
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testConcurrentRequestsShareOneDownload() async {
        ImageStubProtocol.delay = 0.2
        let loader = loader()
        await withTaskGroup(of: UIImage?.self) { group in
            for size in [100, 100, 100, 200] {
                group.addTask { await loader.image(url: self.url, maxPixelSize: size) }
            }
            for await image in group { XCTAssertNotNil(image) }
        }
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    /// A card leaving the screen or being refreshed must not throw away a slow download.
    func testCancellingTheOnlyWaiterKeepsTheDownload() async throws {
        ImageStubProtocol.delay = 0.5
        let loader = loader()
        let task = Task { await loader.image(url: url, maxPixelSize: 100) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let image = await task.value
        XCTAssertNil(image)
        // Asking again uses what that download fetched: still the one request.
        let again = await loader.image(url: url, maxPixelSize: 100)
        XCTAssertNotNil(again)
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testCancellingOneWaiterKeepsItForTheOther() async throws {
        ImageStubProtocol.delay = 0.5
        let loader = loader()
        let leaving = Task { await loader.image(url: url, maxPixelSize: 100) }
        let staying = Task { await loader.image(url: url, maxPixelSize: 100) }
        try await Task.sleep(for: .milliseconds(100))
        leaving.cancel()
        let image = await staying.value
        XCTAssertNotNil(image)
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }

    func testPrefetchFillsTheCache() async throws {
        let loader = loader()
        loader.prefetch(urls: [url], maxPixelSize: 100)
        for _ in 0..<50 where loader.cached(url: url, maxPixelSize: 100) == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotNil(loader.cached(url: url, maxPixelSize: 100))
    }

    func testHttpErrorsAndNonImagesAreNotCached() async {
        let loader = loader()
        ImageStubProtocol.status = 404
        let notFound = await loader.image(url: url, maxPixelSize: 100)
        XCTAssertNil(notFound)
        XCTAssertTrue(files.isEmpty)
        ImageStubProtocol.status = 200
        ImageStubProtocol.body = Data("<html>not an image</html>".utf8)
        let notAnImage = await loader.image(url: url, maxPixelSize: 100)
        XCTAssertNil(notAnImage)
        XCTAssertTrue(files.isEmpty)
    }

    func testTrimEvictsLeastRecentlyUsedFirst() async throws {
        let size = Int64(ImageStubProtocol.body.count)
        // Fits two, so a third download goes over.
        let loader = loader(diskLimit: size * 2 + size / 2)
        let a = URL(string: "https://i.redd.it/a.png")!, b = URL(string: "https://i.redd.it/b.png")!, c = URL(string: "https://i.redd.it/c.png")!
        _ = await loader.image(url: a, maxPixelSize: 10)
        _ = await loader.image(url: b, maxPixelSize: 10)
        // Older dates than the filesystem's granularity could tell apart; a is the oldest.
        for (i, file) in files.enumerated() {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(-1000 - i))], ofItemAtPath: file.path)
        }
        // Using a again (another size: memory misses, disk hits) makes b the oldest.
        _ = await loader.image(url: a, maxPixelSize: 20)
        _ = await loader.image(url: c, maxPixelSize: 10)
        loader.clearMemory()
        ImageStubProtocol.requests = 0
        _ = await loader.image(url: a, maxPixelSize: 10)
        XCTAssertEqual(ImageStubProtocol.requests, 0, "a was used recently")
        _ = await loader.image(url: b, maxPixelSize: 10)
        XCTAssertEqual(ImageStubProtocol.requests, 1, "b was the least recently used")
    }

    func testAnimatedGifPlaysOrStaysStill() async throws {
        let gif = try XCTUnwrap(gifData(frames: 3))
        ImageStubProtocol.body = gif
        let loader = loader()
        let stillLoaded = await loader.image(url: url, maxPixelSize: 50)
        let still = try XCTUnwrap(stillLoaded)
        XCTAssertNil(still.images)
        let animatedLoaded = await loader.image(url: url, maxPixelSize: 50, animated: true)
        let animated = try XCTUnwrap(animatedLoaded)
        XCTAssertEqual(animated.images?.count, 3)
        XCTAssertEqual(animated.duration, 0.3, accuracy: 0.01)
    }

    func testAnimationIsCappedByBytes() async throws {
        ImageStubProtocol.body = try XCTUnwrap(gifData(frames: 3))
        let frameBytes = 64 * 64 * 4
        // Room for two of the three 64×64 frames: every other frame, same running time.
        let twoFrames = await loader(animationBudget: frameBytes * 2 + 100).image(url: url, maxPixelSize: 64, animated: true)
        let animated = try XCTUnwrap(twoFrames)
        XCTAssertEqual(Set(try XCTUnwrap(animated.images)).count, 2)
        XCTAssertEqual(animated.duration, 0.3, accuracy: 0.01)
        // Not even two fit: frame 0, still.
        let oneFrame = await loader(animationBudget: frameBytes).image(url: url, maxPixelSize: 64, animated: true)
        let still = try XCTUnwrap(oneFrame)
        XCTAssertNil(still.images)
        XCTAssertEqual(still.size.width, 64)
    }

    private func gifData(frames: Int) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, frames, nil),
              let cg = UIImage(data: png(width: 64, height: 64))?.cgImage else { return nil }
        for _ in 0..<frames {
            CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
