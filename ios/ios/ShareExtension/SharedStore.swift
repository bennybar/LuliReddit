import Foundation
import Security

/// What Ilay and its "Summarize with Ilay" share extension hand each other,
/// kept in their shared keychain group (an App Group would need the developer
/// portal): the AI settings the extension uses, and the summaries it made for
/// You → Summaries. Compiled into both targets.
enum SharedStore {
  static let aiSettings = "ai_settings"
  static let pendingSummaries = "pending_summaries"

  private static func query(_ key: String) -> [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: "ilay_shared", kSecAttrAccount: key]
  }

  static func read(_ key: String) -> Data? {
    var q = query(key)
    q[kSecReturnData] = true
    q[kSecMatchLimit] = kSecMatchLimitOne
    var out: CFTypeRef?
    return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
  }

  /// Replaces [key] with [data]; nil removes it.
  static func write(_ key: String, _ data: Data?) {
    SecItemDelete(query(key) as CFDictionary)
    guard let data else { return }
    var q = query(key)
    q[kSecValueData] = data
    q[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(q as CFDictionary, nil)
  }
}
