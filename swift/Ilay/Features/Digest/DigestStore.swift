import Foundation
import Observation

/// The last `keep` days' digests, per account, on this device only: each day's posts (as
/// Reddit sent them, so they show without asking again) and everything judged that day
/// (so a refresh only judges what's new). One file per account, the same format as the
/// Kotlin app's.
@MainActor @Observable
final class DigestStore {
    static let keep = 7

    @ObservationIgnored private let io = DispatchQueue(label: "ilay.digest")
    @ObservationIgnored private let filesDir: URL
    @ObservationIgnored private var file: URL
    @ObservationIgnored private let raw: (String) -> JsonElement?
    /// Raw post JSON by id, for posts loaded from the file (the repository only keeps recent ones).
    @ObservationIgnored private var rawCache: [String: JsonElement] = [:]

    /// Newest first.
    private(set) var days: [DigestDay] = []
    /// Reading the account's file: a build waits for it, or it would replace what's saved.
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(filesDir: URL = FileLocations.files, raw: @escaping (String) -> JsonElement?) {
        self.filesDir = filesDir
        self.raw = raw
        file = filesDir.appendingPathComponent("digest_.json")
    }

    func today(_ day: String) -> DigestDay? { days.first { $0.day == day } }

    /// Saves `d`, replacing its day; keeps the newest `keep`.
    func put(_ d: DigestDay) {
        days = Array(([d] + days.filter { $0.day != d.day }).sorted { $0.day > $1.day }.prefix(Self.keep))
        save()
    }

    func markSeen(_ day: String, at: Int) {
        guard var d = today(day), d.seenAt < at else { return }
        d.seenAt = at
        put(d)
    }

    func onUserChanged(_ username: String) {
        let f = filesDir.appendingPathComponent("digest_\(username.lowercased()).json")
        file = f
        days = []
        loading = Task { [weak self, io] in
            let json: JsonElement? = await withCheckedContinuation { done in
                io.async { done.resume(returning: (try? Data(contentsOf: f)).flatMap { try? AppJson.parse($0) }) }
            }
            guard let self, self.file == f, let json else { return }
            self.days = self.decode(json)
        }
    }

    /// Returns once the account's file has been read.
    func loaded() async { await loading?.value }

    private func save() {
        let f = file
        let json = encode(days)
        io.async {
            // Atomic: written to a temp file and swapped in, so a crash mid-write can't truncate it.
            try? Data(json.utf8).write(to: f, options: .atomic)
        }
    }

    private func rawFor(_ id: String) -> JsonElement? {
        if let r = rawCache[id] { return r }
        let r = raw(id)
        if let r { rawCache[id] = r }
        return r
    }

    private func encode(_ days: [DigestDay]) -> String {
        JsonElement.object([
            "days": .array(days.map { d in
                var judged = JsonObject()
                for (id, j) in d.judged {
                    judged[id] = .array([.int(j.picked ? 1 : 0), .double(j.notability), .int(j.at), .int(j.secondLook ? 1 : 0)])
                }
                return .object([
                    "day": .string(d.day),
                    "built": .int(d.builtAt),
                    "refreshed": .int(d.refreshedAt),
                    "seen": .int(d.seenAt),
                    "items": .array(d.items.compactMap { it in
                        guard let r = rawFor(it.post.id) else { return nil }
                        return .object(["raw": r, "why": .string(it.why), "n": .double(it.notability), "at": .int(it.addedAt)])
                    }),
                    "judged": .object(judged),
                ])
            }),
        ]).encoded()
    }

    private func decode(_ json: JsonElement) -> [DigestDay] {
        (json["days"].arr() ?? []).compactMap { d in
            guard let day = d["day"].str() else { return nil }
            let items: [DigestItem] = (d["items"].arr() ?? []).compactMap { i in
                guard let r = i["raw"] else { return nil }
                let post = Post.fromData(r)
                if post.id.isEmpty { return nil }
                rawCache[post.id] = r
                return DigestItem(post: post, why: i["why"].str() ?? "", notability: i["n"].double() ?? 0, addedAt: i["at"].long() ?? 0)
            }
            var judged: [String: Judged] = [:]
            for (id, v) in d["judged"].obj() ?? JsonObject() {
                guard let a = v.arr(), a.count >= 3 else { continue }
                judged[id] = Judged(picked: a[0].long() == 1, notability: a[1].double() ?? 0, at: a[2].long() ?? 0, secondLook: a.count > 3 && a[3].long() == 1)
            }
            return DigestDay(
                day: day,
                builtAt: d["built"].long() ?? 0,
                refreshedAt: d["refreshed"].long() ?? 0,
                seenAt: d["seen"].long() ?? 0,
                items: items,
                judged: judged
            )
        }
    }
}
