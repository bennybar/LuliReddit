import Foundation

/// The Safari extension's native side. Everything happens in Resources/content.js;
/// Safari still needs a handler to load the extension, so it answers with nothing.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    context.completeRequest(returningItems: nil)
  }
}
