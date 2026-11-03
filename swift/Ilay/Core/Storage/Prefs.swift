import Foundation

/// A stored value with its real type, for backups.
enum PrefValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case list([String])
}

/// The app's plain key/value store — the Flutter build's SharedPreferences,
/// read in place. On iOS the plugin keeps every value natively in
/// UserDefaults.standard as `flutter.<key>`: bools as Bool, ints as integers,
/// doubles as reals, string lists as arrays of strings (no tagged strings like
/// on Android). Keys and value types are identical to the Flutter and Android
/// builds (`themeMode` int, `history_<user>` string list, …) so a backup made
/// by any of them restores into the others. A wrong-typed value reads as absent.
final class Prefs: @unchecked Sendable {
    static let prefix = "flutter."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func stored(_ key: String) -> Any? { defaults.object(forKey: Prefs.prefix + key) }

    private func isBoolean(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    func contains(_ key: String) -> Bool { stored(key) != nil }

    func getBool(_ key: String) -> Bool? {
        guard let n = stored(key) as? NSNumber, isBoolean(n) else { return nil }
        return n.boolValue
    }

    /// Dart ints are 64-bit (e.g. ARGB seed colours).
    func getLong(_ key: String) -> Int? {
        guard let n = stored(key) as? NSNumber, !isBoolean(n), !CFNumberIsFloatType(n) else { return nil }
        return n.intValue
    }

    func getInt(_ key: String) -> Int? { getLong(key) }

    func getDouble(_ key: String) -> Double? {
        guard let n = stored(key) as? NSNumber, !isBoolean(n), CFNumberIsFloatType(n) else { return nil }
        return n.doubleValue
    }

    func getString(_ key: String) -> String? { stored(key) as? String }

    func getStringList(_ key: String) -> [String]? {
        guard let a = stored(key) as? [Any] else { return nil }
        return a.compactMap { $0 as? String }
    }

    func setBool(_ key: String, _ v: Bool) { defaults.set(v, forKey: Prefs.prefix + key) }
    func setLong(_ key: String, _ v: Int) { defaults.set(v, forKey: Prefs.prefix + key) }
    func setInt(_ key: String, _ v: Int) { setLong(key, v) }
    func setDouble(_ key: String, _ v: Double) { defaults.set(v, forKey: Prefs.prefix + key) }
    func setString(_ key: String, _ v: String) { defaults.set(v, forKey: Prefs.prefix + key) }
    func setStringList(_ key: String, _ v: [String]) { defaults.set(v, forKey: Prefs.prefix + key) }

    func remove(_ key: String) { defaults.removeObject(forKey: Prefs.prefix + key) }

    /// Every key (without its `flutter.`) with its decoded value.
    func all() -> [String: PrefValue] {
        var out: [String: PrefValue] = [:]
        for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix(Prefs.prefix) {
            let key = String(k.dropFirst(Prefs.prefix.count))
            switch v {
            case let n as NSNumber:
                out[key] = isBoolean(n) ? .bool(n.boolValue) : CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue)
            case let s as String: out[key] = .string(s)
            case let a as [Any]: out[key] = .list(a.compactMap { $0 as? String })
            default: break
            }
        }
        return out
    }

    func keys() -> Set<String> {
        Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Prefs.prefix) }.map { String($0.dropFirst(Prefs.prefix.count)) })
    }
}
