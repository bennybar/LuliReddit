import Foundation
import os

/// Epoch milliseconds now (Kotlin's System.currentTimeMillis()).
func nowMillis() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

/// Hosted unit tests launch the app: they must not touch the real login or network.
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    || NSClassFromString("XCTestCase") != nil

/// A thrown failure with a readable message (Kotlin's `Exception("…")`).
struct AppException: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Kotlin's data-class `copy`: `post.with { $0.score = 3 }`.
protocol Copyable {}
extension Copyable {
    func with(_ change: (inout Self) -> Void) -> Self {
        var c = self
        change(&c)
        return c
    }
}

/// Kotlin Mutex for async code: held across suspension points, unlike an actor's isolation.
final class AsyncMutex: @unchecked Sendable {
    private struct State {
        var locked = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func lock() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let acquired = state.withLock { s -> Bool in
                if s.locked {
                    s.waiters.append(cont)
                    return false
                }
                s.locked = true
                return true
            }
            if acquired { cont.resume() }
        }
    }

    func unlock() {
        let next = state.withLock { s -> CheckedContinuation<Void, Never>? in
            if s.waiters.isEmpty {
                s.locked = false
                return nil
            }
            return s.waiters.removeFirst()
        }
        next?.resume()
    }
}

/// Where the Flutter build's path_provider put things (same folders on iOS).
enum FileLocations {
    /// getTemporaryDirectory: Library/Caches.
    static var caches: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    /// getApplicationSupportDirectory: Library/Application Support (Android's filesDir).
    static var files: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Regex

/// NSRegularExpression (ICU, as on Android) with Kotlin's Regex conveniences.
struct Re: @unchecked Sendable {
    struct Match {
        let value: String
        /// Group 0 is the whole match; a group that didn't take part is "".
        let groups: [String]
    }

    let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false) {
        regex = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    private func match(_ r: NSTextCheckingResult, _ s: NSString) -> Match {
        let groups = (0..<r.numberOfRanges).map { i -> String in
            let g = r.range(at: i)
            return g.location == NSNotFound ? "" : s.substring(with: g)
        }
        return Match(value: groups[0], groups: groups)
    }

    func contains(_ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    func firstMatch(_ s: String) -> Match? {
        let ns = s as NSString
        return regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)).map { match($0, ns) }
    }

    func allMatches(_ s: String) -> [Match] {
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { match($0, ns) }
    }

    /// The match covering all of [s], or nil (Kotlin's matchEntire).
    func matchEntire(_ s: String) -> Match? {
        let ns = s as NSString
        guard let r = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              r.range.location == 0, r.range.length == ns.length else { return nil }
        return match(r, ns)
    }

    func replace(_ s: String, with transform: (Match) -> String) -> String {
        let ns = s as NSString
        let results = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if results.isEmpty { return s }
        var out = ""
        var pos = 0
        for r in results {
            out += ns.substring(with: NSRange(location: pos, length: r.range.location - pos))
            out += transform(match(r, ns))
            pos = r.range.location + r.range.length
        }
        return out + ns.substring(from: pos)
    }

    func replace(_ s: String, with literal: String) -> String { replace(s) { _ in literal } }

    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var pos = 0
        for r in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: pos, length: r.range.location - pos)))
            pos = r.range.location + r.range.length
        }
        out.append(ns.substring(from: pos))
        return out
    }
}

// MARK: - Kotlin's String helpers

extension String {
    var isBlank: Bool { allSatisfy { $0.isWhitespace } }
    var nilIfEmpty: String? { isEmpty ? nil : self }
    /// Kotlin's String.length: the limits below were tuned in UTF-16 units.
    var length: Int { utf16.count }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var trimmedStart: String {
        let u = unicodeScalars
        guard let i = u.firstIndex(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) else { return "" }
        return String(u[i...])
    }

    var trimmedEnd: String {
        let u = unicodeScalars
        guard let i = u.lastIndex(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) else { return "" }
        return String(u[...i])
    }

    /// Without any of [chars] at either end. By scalar: "\r\n" is one Character in Swift.
    func trimming(_ chars: String) -> String { trimmingCharacters(in: CharacterSet(charactersIn: chars)) }

    func trimmingEnd(_ chars: String) -> String {
        let set = CharacterSet(charactersIn: chars)
        let u = unicodeScalars
        guard let i = u.lastIndex(where: { !set.contains($0) }) else { return "" }
        return String(u[...i])
    }

    func removePrefix(_ prefix: String) -> String { hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self }
    func removeSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }

    func substringBefore(_ d: String) -> String {
        range(of: d).map { String(self[..<$0.lowerBound]) } ?? self
    }

    func substringAfter(_ d: String, missing: String? = nil) -> String {
        range(of: d).map { String(self[$0.upperBound...]) } ?? missing ?? self
    }

    func substringBeforeLast(_ d: String, missing: String? = nil) -> String {
        range(of: d, options: .backwards).map { String(self[..<$0.lowerBound]) } ?? missing ?? self
    }

    /// Lines, on \n, \r\n or \r; "" is one empty line.
    func lines() -> [String] {
        replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    func htmlAmpFixed() -> String { replacingOccurrences(of: "&amp;", with: "&") }
}

extension Sequence where Element: Hashable {
    /// Kotlin's distinct(): first occurrences, in order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension URL {
    /// Android's Uri.pathSegments.
    var segments: [String] { pathComponents.filter { $0 != "/" && !$0.isEmpty } }

    /// Android's Uri.getQueryParameter (decoded).
    func queryParameter(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
