package com.bennybar.luli_for_reddit.auth

import android.content.Context
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.core.storage.SecureStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** The signed-in session. */
data class AuthSession(
    val username: String, // "" when [anonymous]
    /** Browsing without an account (app-only token): read-only. */
    val anonymous: Boolean = false,
) {
    /** Identity for "did the account change?" checks (anonymous is its own identity). */
    val identity: String get() = if (anonymous) "\u0000anon" else username
}

sealed interface SessionState {
    data object Loading : SessionState
    data object LoggedOut : SessionState
    data class LoggedIn(val session: AuthSession) : SessionState
}

/**
 * Owns the auth state (the Kotlin counterpart of Flutter's AuthController):
 * restores the session from secure storage, logs in/out, adds and switches
 * accounts.
 */
class SessionManager(
    private val store: SecureStore,
    private val repo: AuthRepository,
    private val prefs: Prefs,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<SessionState>(SessionState.Loading)
    val state: StateFlow<SessionState> = _state
    private val lock = Mutex()

    val session: AuthSession? get() = (_state.value as? SessionState.LoggedIn)?.session
    val username: String get() = session?.username ?: ""

    /**
     * Durable "an account exists on this device" flag, kept in plain prefs so
     * the UI can tell a real logout from a transient keystore read failure
     * (which must not bounce the user to the login screen).
     */
    val hasAccount: Boolean get() = prefs.getBool(HAS_ACCOUNT) ?: false

    private fun setHasAccount(v: Boolean) = prefs.setBool(HAS_ACCOUNT, v)

    /** Re-reads the session from storage (cold start, and on every resume). */
    fun reload() {
        scope.launch { lock.withLock { _state.value = load() } }
    }

    private suspend fun load(): SessionState {
        val out = SessionState.LoggedOut
        try {
            if (store.authMode() == "anon") {
                if (store.clientId() == null) return out
                setHasAccount(true)
                return SessionState.LoggedIn(AuthSession("", anonymous = true))
            }
            val username = store.username()
            if (username == null) {
                // If the store reads fine and simply holds no account (e.g.
                // restored onto a new phone, where it isn't backed up), clear
                // the flag so the login screen shows instead of an empty Home.
                try {
                    if (!store.hasUsername()) setHasAccount(false)
                } catch (_: Exception) { /* still unreadable: treat as transient */ }
                return out
            }
            if (store.authMode() == "web") {
                val cookie = store.webCookie() ?: return out
                if (username !in store.accounts()) store.upsertWebAccount(username, cookie, store.webModhash())
                setHasAccount(true)
                return SessionState.LoggedIn(AuthSession(username))
            }
            // OAuth (default).
            val refresh = store.refreshToken()
            val token = store.accessToken()
            if (token == null && refresh == null) return out
            // Migrate pre-multi-account installs: ensure the current user is in the map.
            if (refresh != null && username !in store.accounts()) store.upsertAccount(username, refresh)
            setHasAccount(true)
            return SessionState.LoggedIn(AuthSession(username))
        } catch (_: Exception) {
            return out
        }
    }

    /** Website-session login (no API key). [cookie] is captured by the WebView. */
    suspend fun loginWithWebSession(cookie: String) {
        val (username, modhash) = repo.completeWebLogin(cookie)
        store.upsertWebAccount(username, cookie, modhash)
        setHasAccount(true)
        _state.value = SessionState.LoggedIn(AuthSession(username))
    }

    /** The full interactive login (first account or another one). */
    suspend fun login(context: Context, clientId: String, redirectUri: String, ephemeral: Boolean = false) {
        val username = repo.login(context, clientId, redirectUri, ephemeral)
        store.refreshToken()?.let { store.upsertAccount(username, it) }
        setHasAccount(true)
        _state.value = SessionState.LoggedIn(AuthSession(username))
    }

    /** Starts browsing without an account (needs only a Client ID). */
    suspend fun browseAnonymously(clientId: String) {
        repo.startAnonymous(clientId)
        setHasAccount(true)
        _state.value = SessionState.LoggedIn(AuthSession("", anonymous = true))
    }

    /** Adds another account, reusing the saved API credentials. */
    suspend fun addAccount(context: Context) {
        val clientId = store.clientId()
        val redirectUri = store.redirectUri()
        if (clientId == null || redirectUri == null) throw AuthException("No saved API credentials on this device.")
        login(context, clientId, redirectUri, ephemeral = true)
    }

    suspend fun switchAccount(username: String) {
        if (username == session?.username) return
        if (!store.activateAccount(username)) return
        _state.value = SessionState.LoggedIn(AuthSession(username))
    }

    /** Signs out one account; switches to another if any remain. */
    suspend fun removeAccount(username: String) {
        store.removeAccountEntry(username)
        if (username != session?.username) {
            _state.value = _state.value // accounts list changed; screens re-query
            _accountsVersion.value++
            return
        }
        val remaining = store.accounts()
        if (remaining.isEmpty()) {
            store.clearSession()
            store.clearAccounts()
            setHasAccount(false)
            _state.value = SessionState.LoggedOut
        } else {
            store.activateAccount(remaining.first())
            _state.value = SessionState.LoggedIn(AuthSession(remaining.first()))
        }
        _accountsVersion.value++
    }

    /** Full sign-out of every account. */
    suspend fun logout() {
        store.clearSession()
        store.clearAccounts()
        setHasAccount(false)
        _state.value = SessionState.LoggedOut
        _accountsVersion.value++
    }

    private val _accountsVersion = MutableStateFlow(0)

    /** Bumped when the stored account list changes. */
    val accountsVersion: StateFlow<Int> = _accountsVersion

    suspend fun accounts(): List<String> = runCatching { store.accounts() }.getOrDefault(emptyList())

    /** 'oauth' (API key), 'web' (website session) or 'anon'. */
    suspend fun authMode(): String = store.authMode()

    companion object {
        const val HAS_ACCOUNT = "has_account"
    }
}
