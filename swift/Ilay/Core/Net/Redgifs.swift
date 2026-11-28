import Foundation

// RedGifs links point at a web page, not a playable file. Their public API
// hands out an anonymous temporary token, which then resolves a clip id to
// its HD (with sound) / SD mp4.
actor Redgifs {
    static let shared = Redgifs()

    private let session = URLSession(configuration: Http.configuration(timeout: 8))
    private var token: String?
    /// Resolved clips by id: (HD, SD), so a feed scrolled back and forth asks once.
    private var resolved: [String: (hd: String?, sd: String?)] = [:]

    /// The clip id in a RedGifs URL (`/watch/<id>`, `/ifr/<id>`, `i.redgifs.com/i/<id>.jpg`).
    nonisolated static func id(_ url: String) -> String? {
        guard let u = URL(string: url), u.host?.lowercased().hasSuffix("redgifs.com") == true else { return nil }
        let segs = u.segments
        guard segs.count >= 2, ["watch", "ifr", "i"].contains(segs[0]) else { return nil }
        return segs[1].substringBefore(".").substringBefore("-").lowercased().nilIfEmpty
    }

    /// The best playable mp4 for a RedGifs URL, or nil if it can't be resolved.
    /// Both files carry the clip's sound; `hd` false picks the smaller mobile one,
    /// for the feed (#310). Reddit's own copy of the clip is silent.
    func resolve(_ url: String, hd: Bool = true) async -> String? {
        guard let id = Redgifs.id(url) else { return nil }
        if let r = resolved[id] { return hd ? r.hd ?? r.sd : r.sd ?? r.hd }
        // One retry with a fresh token: temporary tokens expire (~24h).
        for _ in 0..<2 {
            do {
                var t = token
                if t == nil {
                    let res = try await session.send(URLRequest(url: URL(string: "https://api.redgifs.com/v2/auth/temporary")!))
                    t = try AppJson.parse(res.body)["token"].str()
                    token = t
                }
                guard let t else { return nil }
                var req = URLRequest(url: URL(string: "https://api.redgifs.com/v2/gifs/\(id)")!)
                req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                let res = try await session.send(req)
                if res.status == 401 {
                    token = nil
                    continue
                }
                guard (200..<300).contains(res.status) else { return nil }
                let urls = try AppJson.parse(res.body)["gif"]["urls"]
                let h = urls["hd"].str(), s = urls["sd"].str()
                if h != nil || s != nil { resolved[id] = (h, s) }
                return hd ? h ?? s : s ?? h
            } catch {
                return nil
            }
        }
        return nil
    }
}
