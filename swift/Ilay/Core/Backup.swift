import Foundation

/// Exports / imports all local prefs — settings, the on-device For You model,
/// history, mutes, content filters, etc. Same file format as the Flutter
/// build, so backups move between them. API credentials and tokens live in
/// secure storage and are intentionally NOT included.
enum Backup {
    private static func skip(_ key: String) -> Bool { key.hasPrefix("draft_") || key.hasPrefix("__") }

    static func export(_ p: Prefs) -> String {
        var data = JsonObject()
        let all = p.all()
        for k in all.keys.sorted() where !skip(k) {
            switch all[k]! {
            case .bool(let v): data[k] = ["t": "b", "v": .bool(v)]
            case .int(let v): data[k] = ["t": "i", "v": .int(v)]
            case .double(let v): data[k] = ["t": "d", "v": .double(v)]
            case .string(let v): data[k] = ["t": "s", "v": .string(v)]
            case .list(let v): data[k] = ["t": "l", "v": .strings(v)]
            }
        }
        let root: JsonElement = ["app": "ilay_for_reddit", "version": 1, "data": .object(data)]
        return root.pretty()
    }

    /// Restores from a backup [json] string. Returns the number of keys written.
    @discardableResult
    static func `import`(_ p: Prefs, _ json: String) throws -> Int {
        guard let data = parseJsonOrNull(json)["data"].obj() else { throw AppException("Not a valid Ilay backup file.") }
        var n = 0
        for (key, m) in data {
            guard let v = m["v"] else { continue }
            switch m["t"].content() {
            case "b": if let x = v.bool() { p.setBool(key, x); n += 1 }
            case "i": if let x = v.long() { p.setLong(key, x); n += 1 }
            case "d": if let x = v.double() { p.setDouble(key, x); n += 1 }
            case "s": if let x = v.str() { p.setString(key, x); n += 1 }
            case "l":
                if let x = v.arr() {
                    p.setStringList(key, x.compactMap { $0.content() })
                    n += 1
                }
            default: break
            }
        }
        return n
    }
}
