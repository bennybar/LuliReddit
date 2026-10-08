package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.storage.Prefs

/**
 * Per-account prefs keys: `<base>_<username lowercase>` ('' suffix while
 * logged out / anonymous), so local data (history, filters, the For You
 * model…) never leaks between accounts. Same scheme as the Flutter build.
 *
 * One-time migration: pre-multi-account installs stored under the bare key.
 */
fun userScopedKey(prefs: Prefs, username: String, base: String): String {
    val key = if (username.isEmpty()) base else "${base}_${username.lowercase()}"
    if (key != base && !prefs.contains(key) && prefs.contains(base)) {
        prefs.getString(base)?.let { prefs.setString(key, it) }
        prefs.getStringList(base)?.let { prefs.setStringList(key, it) }
        prefs.remove(base)
    }
    return key
}

/**
 * A store whose contents belong to the signed-in account. [AppContainer]
 * calls [onUserChanged] on login, account switch and logout.
 */
interface UserScoped {
    fun onUserChanged(username: String)
}
