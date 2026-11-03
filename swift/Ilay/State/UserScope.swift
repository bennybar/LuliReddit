import Foundation

/// Per-account prefs keys: `<base>_<username lowercase>` ('' suffix while
/// logged out / anonymous), so local data (history, filters, the For You
/// model…) never leaks between accounts. Same scheme as the Flutter build.
///
/// One-time migration: pre-multi-account installs stored under the bare key.
func userScopedKey(_ prefs: Prefs, _ username: String, _ base: String) -> String {
    let key = username.isEmpty ? base : "\(base)_\(username.lowercased())"
    if key != base, !prefs.contains(key), prefs.contains(base) {
        if let s = prefs.getString(base) { prefs.setString(key, s) }
        if let l = prefs.getStringList(base) { prefs.setStringList(key, l) }
        prefs.remove(base)
    }
    return key
}

/// A store whose contents belong to the signed-in account. AppContainer
/// calls [onUserChanged] on login, account switch and logout.
@MainActor
protocol UserScoped: AnyObject {
    func onUserChanged(_ username: String)
}
