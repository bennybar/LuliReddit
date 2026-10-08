package com.bennybar.luli_for_reddit.core.storage

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.bennybar.luli_for_reddit.core.AppJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/**
 * Everything sensitive: the user's Reddit API credentials (entered at login),
 * OAuth tokens, website-session cookies and the multi-account map.
 *
 * Reads and writes the very same encrypted file the Flutter build used
 * (flutter_secure_storage 9 with `encryptedSharedPreferences: true`): an
 * androidx EncryptedSharedPreferences named `FlutterSecureStorage`, keys
 * prefixed with [KEY_PREFIX], AES256-SIV/GCM under the default master key.
 * So an existing login simply carries over — nobody has to sign in again.
 */
class SecureStore(private val context: Context) {
    private val mutex = Mutex()
    @Volatile private var prefs: SharedPreferences? = null

    private fun open(): SharedPreferences {
        prefs?.let { return it }
        val key = MasterKey.Builder(context)
            .setKeyGenParameterSpec(
                KeyGenParameterSpec.Builder(
                    MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setKeySize(256)
                    .build(),
            )
            .build()
        return EncryptedSharedPreferences.create(
            context,
            FILE,
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        ).also { prefs = it }
    }

    /**
     * The Keystore can transiently fail right after boot / on a cold start,
     * which used to bounce a logged-in user to the login screen. Retry.
     */
    private suspend fun <T> withPrefs(block: (SharedPreferences) -> T): T = withContext(Dispatchers.IO) {
        var last: Exception? = null
        repeat(3) {
            try {
                return@withContext block(open())
            } catch (e: Exception) {
                last = e
                prefs = null
                delay(150)
            }
        }
        Log.e(TAG, "Secure storage unavailable", last)
        throw last!!
    }

    suspend fun read(key: String): String? = withPrefs { it.getString(KEY_PREFIX + key, null) }

    /** Like [read] but never throws (a failure reads as null). */
    suspend fun readOrNull(key: String): String? = runCatching { read(key) }.getOrNull()

    private suspend fun write(key: String, value: String?) = mutex.withLock {
        withPrefs {
            val e = it.edit()
            if (value == null) e.remove(KEY_PREFIX + key) else e.putString(KEY_PREFIX + key, value)
            e.commit()
        }
    }

    private suspend fun delete(vararg keys: String) = mutex.withLock {
        withPrefs { p ->
            val e = p.edit()
            keys.forEach { e.remove(KEY_PREFIX + it) }
            e.commit()
        }
    }

    /** Whether a username is stored. Unlike [username], a read failure throws. */
    suspend fun hasUsername(): Boolean = withPrefs { it.contains(KEY_PREFIX + K_USERNAME) }

    // --- API credentials ---
    suspend fun clientId(): String? = readOrNull(K_CLIENT_ID)
    suspend fun redirectUri(): String? = readOrNull(K_REDIRECT_URI)
    suspend fun giphyKey(): String? = readOrNull(K_GIPHY_KEY)

    /** OpenAI (or compatible) API key for AI thread summaries. Account-independent. */
    suspend fun openaiKey(): String? = readOrNull(K_OPENAI_KEY)
    suspend fun saveOpenaiKey(value: String?) = write(K_OPENAI_KEY, value?.ifEmpty { null })

    suspend fun saveGiphyKey(value: String?) = write(K_GIPHY_KEY, value?.ifEmpty { null })

    suspend fun saveCredentials(clientId: String, redirectUri: String, giphyKey: String? = null) {
        write(K_CLIENT_ID, clientId)
        write(K_REDIRECT_URI, redirectUri)
        write(K_GIPHY_KEY, giphyKey?.ifEmpty { null })
    }

    // --- Tokens ---
    suspend fun accessToken(): String? = readOrNull(K_ACCESS_TOKEN)
    suspend fun refreshToken(): String? = readOrNull(K_REFRESH_TOKEN)
    suspend fun username(): String? = readOrNull(K_USERNAME)

    /** Access-token expiry, millis since epoch. */
    suspend fun tokenExpiry(): Long? = readOrNull(K_TOKEN_EXPIRY)?.toLongOrNull()

    suspend fun saveTokens(accessToken: String, refreshToken: String?, expiryMillis: Long) {
        write(K_ACCESS_TOKEN, accessToken)
        if (refreshToken != null) write(K_REFRESH_TOKEN, refreshToken)
        write(K_TOKEN_EXPIRY, expiryMillis.toString())
    }

    suspend fun saveUsername(username: String?) = write(K_USERNAME, username)

    // --- Auth mode + website session (no-API-key fallback) ---
    /** 'oauth' (default), 'web', or 'anon' (browsing without an account). */
    suspend fun authMode(): String = readOrNull(K_AUTH_MODE) ?: "oauth"
    suspend fun webCookie(): String? = readOrNull(K_WEB_COOKIE)
    suspend fun webModhash(): String? = readOrNull(K_WEB_MODHASH)

    suspend fun saveWebSession(username: String, cookie: String, modhash: String?) {
        write(K_AUTH_MODE, "web")
        write(K_WEB_COOKIE, cookie)
        write(K_WEB_MODHASH, modhash)
        write(K_USERNAME, username)
        delete(K_ACCESS_TOKEN, K_REFRESH_TOKEN, K_TOKEN_EXPIRY)
    }

    /** Browsing without an account: an app-only token, no user/refresh/cookie. */
    suspend fun saveAnonymousSession() {
        write(K_AUTH_MODE, "anon")
        delete(K_REFRESH_TOKEN, K_USERNAME, K_WEB_COOKIE, K_WEB_MODHASH)
    }

    // --- Multi-account ---
    // {username: account} where each value is an OAuth account
    // {"mode":"oauth","rt":...} or a website-session account
    // {"mode":"web","cookie":...,"modhash":...}. Legacy plain-string values are
    // an OAuth refresh token. The "active slot" keys mirror the current account.

    private suspend fun accountsMap(): MutableMap<String, JsonObject> {
        val raw = readOrNull(K_ACCOUNTS)
        if (raw.isNullOrEmpty()) return linkedMapOf()
        return try {
            val m = AppJson.parseToJsonElement(raw).jsonObject
            m.mapValuesTo(linkedMapOf()) { (_, v) ->
                (v as? JsonObject) ?: buildJsonObject {
                    put("mode", "oauth")
                    put("rt", (v as? JsonPrimitive)?.content)
                }
            }
        } catch (_: Exception) {
            linkedMapOf()
        }
    }

    private suspend fun saveAccounts(m: Map<String, JsonElement>) = write(K_ACCOUNTS, JsonObject(m).toString())

    suspend fun accounts(): List<String> = accountsMap().keys.toList()

    suspend fun accountMode(username: String): String? =
        (accountsMap()[username]?.get("mode") as? JsonPrimitive)?.content

    suspend fun upsertAccount(username: String, refreshToken: String) {
        val m = accountsMap()
        m[username] = buildJsonObject { put("mode", "oauth"); put("rt", refreshToken) }
        saveAccounts(m)
    }

    suspend fun upsertWebAccount(username: String, cookie: String, modhash: String?) {
        val m = accountsMap()
        m[username] = buildJsonObject { put("mode", "web"); put("cookie", cookie); put("modhash", modhash) }
        saveAccounts(m)
    }

    suspend fun removeAccountEntry(username: String) {
        val m = accountsMap()
        m.remove(username)
        saveAccounts(m)
    }

    suspend fun clearAccounts() = delete(K_ACCOUNTS)

    /** Loads [username]'s stored credentials into the active slot. False if unknown. */
    suspend fun activateAccount(username: String): Boolean {
        val acct = accountsMap()[username] ?: return false
        fun field(k: String) = (acct[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
        val mode = field("mode") ?: "oauth"
        write(K_USERNAME, username)
        delete(K_ACCESS_TOKEN, K_TOKEN_EXPIRY)
        if (mode == "web") {
            write(K_AUTH_MODE, "web")
            write(K_WEB_COOKIE, field("cookie"))
            write(K_WEB_MODHASH, field("modhash"))
            delete(K_REFRESH_TOKEN)
        } else {
            write(K_AUTH_MODE, "oauth")
            write(K_REFRESH_TOKEN, field("rt"))
            delete(K_WEB_COOKIE, K_WEB_MODHASH)
        }
        return true
    }

    /** Clears the active session but keeps API credentials so re-login is quick. */
    suspend fun clearSession() =
        delete(K_ACCESS_TOKEN, K_REFRESH_TOKEN, K_TOKEN_EXPIRY, K_USERNAME, K_WEB_COOKIE, K_WEB_MODHASH, K_AUTH_MODE)

    /** Full wipe — credentials and session. */
    suspend fun clearAll() = mutex.withLock { withPrefs { it.edit().clear().commit() } }

    companion object {
        private const val TAG = "SecureStore"
        const val FILE = "FlutterSecureStorage"
        const val KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_"

        private const val K_CLIENT_ID = "client_id"
        private const val K_REDIRECT_URI = "redirect_uri"
        private const val K_GIPHY_KEY = "giphy_api_key"
        private const val K_OPENAI_KEY = "openai_api_key"
        private const val K_ACCESS_TOKEN = "access_token"
        private const val K_REFRESH_TOKEN = "refresh_token"
        private const val K_TOKEN_EXPIRY = "token_expiry"
        private const val K_USERNAME = "username"
        private const val K_AUTH_MODE = "auth_mode"
        private const val K_WEB_COOKIE = "web_cookie"
        private const val K_WEB_MODHASH = "web_modhash"
        private const val K_ACCOUNTS = "accounts_json"
    }
}
