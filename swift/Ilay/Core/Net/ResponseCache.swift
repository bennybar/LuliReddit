import CryptoKit
import Foundation

/// Tiny on-disk JSON cache for GET responses: painted instantly on open and
/// used as a fallback when the network is unavailable. Same directory and
/// key hashing as the Flutter build (caches/luli_cache/<md5>.json), so its
/// cache carries over. Async methods run off the main actor.
final class ResponseCache: Sendable {
    private let cacheDir: URL

    init(cacheDir: URL) { self.cacheDir = cacheDir }

    private var dir: URL {
        let d = cacheDir.appendingPathComponent("luli_cache")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func file(_ key: String) -> URL {
        let md5 = Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(md5).json")
    }

    func write(_ key: String, _ json: Data) async {
        try? json.write(to: file(key), options: .atomic) // best-effort
    }

    func read(_ key: String) async -> JsonElement? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? AppJson.parse(data)
    }

    func clear() async {
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("luli_cache"))
    }
}
