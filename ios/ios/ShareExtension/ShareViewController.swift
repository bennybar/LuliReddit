import UIKit
import UniformTypeIdentifiers

/// "Open in Ilay" in the share sheet: finds the Reddit link in what was shared
/// and opens Ilay on it, luli://share?url=<link>. The app does the rest.
/// ("Summarize with Ilay" is SummarizeViewController, which uses the helpers
/// here too.)
class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { @MainActor in
      if let link = await Self.sharedLink(extensionContext) {
        Self.openInIlay(link, summarize: false, from: self)
      }
      extensionContext?.completeRequest(returningItems: nil)
    }
  }

  /// The Reddit link in what was shared: apps share a post as a URL, or as
  /// text ("title https://…").
  static func sharedLink(_ context: NSExtensionContext?) async -> URL? {
    let items = context?.inputItems as? [NSExtensionItem] ?? []
    for provider in items.flatMap({ $0.attachments ?? [] }) {
      for type in [UTType.url, UTType.plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
        let item = try? await provider.loadItem(forTypeIdentifier: type.identifier)
        let text = (item as? URL)?.absoluteString ?? (item as? String) ?? ""
        if let url = redditLink(in: text) { return url }
      }
    }
    return nil
  }

  static func redditLink(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    return matches.compactMap(\.url).first { url in
      let h = url.host?.lowercased() ?? ""
      return h == "reddit.com" || h.hasSuffix(".reddit.com") || h == "redd.it" || h.hasSuffix(".redd.it")
    }
  }

  /// Opens Ilay on [link] (with its summary when [summarize]).
  static func openInIlay(_ link: URL, summarize: Bool, from responder: UIResponder) {
    // Encoded whole: the link has its own ?query&params.
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let encoded = link.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    if let url = URL(string: "luli://share?url=\(encoded)\(summarize ? "&summarize=1" : "")") {
      open(url, from: responder)
    }
  }

  /// An extension can't use UIApplication.shared; the app object is up the
  /// responder chain, and its openURL is called through the runtime.
  private static func open(_ url: URL, from responder: UIResponder) {
    let sel = NSSelectorFromString("openURL:options:completionHandler:")
    var r: UIResponder? = responder
    while let next = r {
      if let app = next as? UIApplication, app.responds(to: sel) {
        typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        unsafeBitCast(app.method(for: sel), to: Open.self)(app, sel, url as NSURL, NSDictionary(), nil)
        return
      }
      r = next.next
    }
  }
}
