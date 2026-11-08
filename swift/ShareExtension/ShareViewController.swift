import UIKit
import UniformTypeIdentifiers

/// Helpers for "Ilay" in the share sheet (SummarizeViewController): find the
/// Reddit link in what was shared and open Ilay on it, luli://share?url=<link>
/// (the Debug build's own scheme there). The app does the rest.
/// (It was also the "Open in Ilay" extension, now merged into that one.)
class ShareViewController: UIViewController {

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
    let scheme = Bundle.main.object(forInfoDictionaryKey: "IlayAppUrlScheme") as? String ?? "luli"
    if let url = shareUrl(link, summarize: summarize, scheme: scheme) {
      open(url, from: responder)
    }
  }

  static func shareUrl(_ link: URL, summarize: Bool, scheme: String) -> URL? {
    // Encoded whole: the link has its own ?query&params.
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let encoded = link.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    return URL(string: "\(scheme)://share?url=\(encoded)\(summarize ? "&summarize=1" : "")")
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
