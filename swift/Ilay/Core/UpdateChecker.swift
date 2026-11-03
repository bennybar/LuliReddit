import Foundation

struct UpdateInfo: Sendable {
    let version: String
    let url: String // release page
    let apkUrl: String? // direct .apk asset if present
}

/// Checks GitHub Releases for a newer version.
///
/// GitHub releases are the Android app's: on iOS the Flutter build never checks
/// on its own (`if (!Platform.isAndroid) return` at startup) and only answers
/// Settings → Check for updates. Keep it that way: don't call this at launch.
///
/// A stable build only looks at the latest stable release. A prerelease build
/// (e.g. 2.0.0-beta1) also considers newer prereleases, so beta testers get
/// the next beta.
enum UpdateChecker {
    static func check(currentVersion: String = RedditConstants.appVersion) async -> UpdateInfo? {
        let isPre = currentVersion.contains("-")
        let url = "https://api.github.com/repos/\(RedditConstants.githubRepo)/releases" + (isPre ? "?per_page=20" : "/latest")
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let res = try? await Http.session.send(req), (200..<300).contains(res.status),
              let json = try? AppJson.parse(res.body) else { return nil }
        let releases = isPre ? json.arr() ?? [] : [json]
        var best: JsonElement?
        for r in releases where r["draft"].bool() != true {
            if best == nil || compareVersions(tagOf(best!), tagOf(r)) < 0 { best = r }
        }
        guard let best else { return nil }
        let tag = tagOf(best)
        if tag.isEmpty || compareVersions(tag, currentVersion) <= 0 { return nil }
        // The LARGEST .apk is the universal build; the smaller ones are per-ABI splits.
        let apk = (best["assets"].arr() ?? [])
            .filter { $0["name"].str()?.lowercased().hasSuffix(".apk") == true }
            .max { ($0["size"].long() ?? 0) < ($1["size"].long() ?? 0) }?["browser_download_url"].str()
        return UpdateInfo(version: tag, url: best["html_url"].str() ?? "https://github.com/\(RedditConstants.githubRepo)/releases", apkUrl: apk)
    }

    private static func tagOf(_ release: JsonElement) -> String { (release["tag_name"].str() ?? "").removePrefix("v").trimmed }

    /// Semver-ish: 1.0.51 < 2.0.0-beta1 < 2.0.0-beta2 < 2.0.0.
    /// A prerelease sorts before the same version without a suffix.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        func parts(_ v: String) -> ([Int], String?) {
            (v.substringBefore("-").components(separatedBy: ".").map { Int($0) ?? 0 }, v.substringAfter("-", missing: "").nilIfEmpty)
        }
        func order<T: Comparable>(_ x: T, _ y: T) -> Int { x < y ? -1 : x > y ? 1 : 0 }
        let (ma, pa) = parts(a)
        let (mb, pb) = parts(b)
        for i in 0..<3 {
            let x = i < ma.count ? ma[i] : 0
            let y = i < mb.count ? mb[i] : 0
            if x != y { return order(x, y) }
        }
        switch (pa, pb) {
        case (nil, nil): return 0
        case (nil, _): return 1
        case (_, nil): return -1
        case let (pa?, pb?):
            let na = Int(pa.filter(\.isNumber)) ?? 0
            let nb = Int(pb.filter(\.isNumber)) ?? 0
            let la = pa.filter(\.isLetter)
            let lb = pb.filter(\.isLetter)
            return la != lb ? order(la, lb) : order(na, nb)
        }
    }
}
