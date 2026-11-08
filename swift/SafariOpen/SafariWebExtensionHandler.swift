import Foundation
import SafariServices

/// The Safari extension's native side: background.js asks it for Settings →
/// "Safari extension: ask which app" (the app leaves it in the shared keychain).
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    let ask = SharedStore.read(SharedStore.safariAsk).map { String(decoding: $0, as: UTF8.self) } == "1"
    let reply = NSExtensionItem()
    reply.userInfo = [SFExtensionMessageKey: ["ask": ask]]
    context.completeRequest(returningItems: [reply])
  }
}
