import SwiftUI
import UIKit

/// "Summarize with Ilay" in the share sheet: the AI summary of the shared post
/// in a sheet over the app it was shared from, without opening Ilay. A Swift
/// port of the app's summary (ask_thread_sheet.dart, ai_service.dart): it uses
/// the app's website session, OpenAI key and AI settings from the shared
/// keychain (SharedStore), and leaves the summary there for You → Summaries.
class SummarizeViewController: UIViewController {
  private let model = SummaryModel()
  private var finished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    let root = SummaryView(
      model: model,
      close: { [weak self] in self?.finish() },
      open: { [weak self] link, summarize in
        guard let self else { return }
        ShareViewController.openInIlay(link, summarize: summarize, from: self)
        self.finish()
      })
    let host = UIHostingController(rootView: root)
    addChild(host)
    host.view.frame = view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(host.view)
    host.didMove(toParent: self)
    Task { @MainActor in
      model.link = await ShareViewController.sharedLink(extensionContext)
      await model.run()
    }
  }

  // Swiped down rather than closed: still finish the request, or the share
  // sheet stays up behind it.
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    finish()
  }

  /// Done (once): the share sheet closes with it.
  private func finish() {
    guard !finished else { return }
    finished = true
    extensionContext?.completeRequest(returningItems: [])
  }
}

// MARK: - Shared with the app

/// An item the app keeps with flutter_secure_storage (its default service).
private func keychain(_ key: String) -> String? {
  let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "flutter_secure_storage_service",
    kSecAttrAccount: key,
    kSecReturnData: true,
    kSecMatchLimit: kSecMatchLimitOne,
  ]
  var out: CFTypeRef?
  guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
  return String(data: data, encoding: .utf8)
}

/// Settings → AI summaries, as the app last left them (AppDelegate copies
/// them; defaults as in settings_controller.dart).
private struct AiSettings {
  let model, baseUrl, language, commentSort: String
  let style, maxChars: Int

  init() {
    let d = SharedStore.read(SharedStore.aiSettings)
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    model = d["aiModel"] as? String ?? "gpt-5.4-mini"
    let custom = d["aiUseCustomUrl"] as? Bool ?? false
    baseUrl = custom ? (d["aiBaseUrl"] as? String ?? "https://api.openai.com") : "https://api.openai.com"
    language = d["aiSummaryLanguage"] as? String ?? ""
    commentSort = d["defaultCommentSort"] as? String ?? "confidence"
    style = min(max(d["aiSummaryStyle"] as? Int ?? 1, 0), SummaryStyle.allCases.count - 1)
    maxChars = d["aiMaxChars"] as? Int ?? 100_000
  }
}

/// Same as the app's SummaryStyle (ai_service.dart).
private enum SummaryStyle: Int, CaseIterable {
  case tldr, points, debate, eli5

  var label: String {
    switch self {
    case .tldr: return "TL;DR"
    case .points: return "Key points"
    case .debate: return "Consensus & disagreements"
    case .eli5: return "Explain like I'm 5"
    }
  }

  var instruction: String {
    switch self {
    case .tldr: return "Give a tight 2-4 sentence TL;DR of the discussion."
    case .points:
      return "Summarize as concise markdown bullet points: the post in one line, "
        + "then the main takeaways, notable opinions, and any useful facts "
        + "or links raised in the comments."
    case .debate:
      return "Summarize what the commenters broadly agree on, then the main points "
        + "of disagreement or debate, as short markdown sections."
    case .eli5:
      return "Explain the post and what people are saying in simple, plain language "
        + "anyone could understand."
    }
  }
}

private struct SummaryError: LocalizedError {
  let errorDescription: String?
  /// Ilay itself can do it (e.g. signed in with an API key): offer that.
  var openApp = false
  init(_ message: String, openApp: Bool = false) {
    errorDescription = message
    self.openApp = openApp
  }
}

// MARK: - The summary

private struct SharedPost {
  let id, subreddit, title, permalink: String
}

@MainActor
private final class SummaryModel: ObservableObject {
  var link: URL?
  @Published var stage = "Loading the thread…"
  @Published var loading = true
  @Published var text: String?
  @Published var error: SummaryError?
  @Published var post: SharedPost?
  let settings = AiSettings()
  var style: SummaryStyle { SummaryStyle(rawValue: settings.style) ?? .points }

  func run() async {
    loading = true
    error = nil
    stage = "Loading the thread…"
    do {
      let summary = try await summarize()
      text = summary
    } catch let e as SummaryError {
      error = e
    } catch {
      self.error = SummaryError(error.localizedDescription)
    }
    loading = false
  }

  private func summarize() async throws -> String {
    guard var url = link else { throw SummaryError("There's no Reddit link in what was shared.") }
    // Website sign-in only: an API-key session needs token refreshes the app
    // does; Ilay can summarize the post itself.
    guard keychain("auth_mode") == "web", let cookie = keychain("web_cookie") else {
      throw SummaryError("Summarizing here needs Ilay's website sign-in. Ilay can summarize it instead.", openApp: true)
    }
    guard let key = keychain("openai_api_key"), !key.isEmpty else {
      throw SummaryError("Add an OpenAI key in Ilay's Settings → AI summaries.")
    }
    // Share links (/r/<sub>/s/<code>) redirect to the real post first.
    if Self.isShareLink(url) { url = try await Self.resolve(url) }
    guard let id = Self.postId(url) else { throw SummaryError("That link isn't a Reddit post.") }
    let (post, threadText) = try await thread(id, cookie: cookie)
    self.post = post
    stage = "Summarizing…"
    let summary = try await chat(key: key, threadText: threadText)
    Self.keep(post, summary: summary, style: style, model: settings.model)
    return summary
  }

  // MARK: Reddit

  private static let webUserAgent =
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

  private static func isShareLink(_ url: URL) -> Bool {
    let s = url.pathComponents.filter { $0 != "/" }
    return s.count >= 4 && s[0] == "r" && s[2] == "s"
  }

  /// Where a share link redirects (URLSession follows it).
  private static func resolve(_ url: URL) async throws -> URL {
    for method in ["HEAD", "GET"] {
      var req = URLRequest(url: url)
      req.httpMethod = method
      req.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
      if let final = try? await URLSession.shared.data(for: req).1.url, !isShareLink(final) { return final }
    }
    throw SummaryError("Couldn't open that link.")
  }

  /// The post id in a reddit.com / redd.it post link.
  private static func postId(_ url: URL) -> String? {
    let s = url.pathComponents.filter { $0 != "/" }
    if url.host?.lowercased() == "redd.it" { return s.first }
    if let i = s.firstIndex(of: "comments"), i + 1 < s.count { return s[i + 1] }
    if s.count >= 2 && s[0] == "gallery" { return s[1] }
    return nil
  }

  /// The post and the thread text to summarize (AiService.buildThreadText):
  /// the post, then comments by score until the max length.
  private func thread(_ id: String, cookie: String) async throws -> (SharedPost, String) {
    var c = URLComponents(string: "https://www.reddit.com/comments/\(id).json")!
    c.queryItems = [
      URLQueryItem(name: "sort", value: settings.commentSort),
      URLQueryItem(name: "limit", value: "500"),
      URLQueryItem(name: "raw_json", value: "1"),
    ]
    var req = URLRequest(url: c.url!)
    req.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue(cookie, forHTTPHeaderField: "Cookie")
    req.httpShouldHandleCookies = false
    let (data, res) = try await URLSession.shared.data(for: req)
    let status = (res as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw SummaryError(status == 403 || status == 404
        ? "Reddit wouldn't load this post (\(status))." : "Couldn't load the thread (HTTP \(status)).")
    }
    guard let body = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], body.count >= 2,
          let p = ((body[0]["data"] as? [String: Any])?["children"] as? [[String: Any]])?.first?["data"] as? [String: Any]
    else { throw SummaryError("Couldn't read the thread.") }

    var comments: [(score: Int, author: String, body: String)] = []
    func walk(_ listing: Any?) {
      let children = ((listing as? [String: Any])?["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
      for child in children where child["kind"] as? String == "t1" {
        guard let d = child["data"] as? [String: Any] else { continue }
        let text = (d["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          comments.append((d["score"] as? Int ?? 0, d["author"] as? String ?? "", text))
        }
        walk(d["replies"])
      }
    }
    walk(body[1])

    let post = SharedPost(
      id: p["id"] as? String ?? id,
      subreddit: p["subreddit"] as? String ?? "",
      title: p["title"] as? String ?? "",
      permalink: p["permalink"] as? String ?? "/comments/\(id)")
    var sb = "POST in r/\(post.subreddit) by u/\(p["author"] as? String ?? "") — score "
      + "\(p["score"] as? Int ?? 0), \(p["num_comments"] as? Int ?? 0) comments\n"
    sb += "TITLE: \(post.title)\n"
    let selftext = (p["selftext"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if p["is_self"] as? Bool == true && !selftext.isEmpty { sb += "BODY: \(selftext)\n" }
    sb += "\nTOP COMMENTS (most upvoted first):\n"
    let ranked = comments.sorted { $0.score > $1.score }
    var included = 0
    for c in ranked {
      let line = "\n[\(c.score)] u/\(c.author): \(c.body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))"
      if sb.utf16.count + line.utf16.count > settings.maxChars { break }
      sb += line
      included += 1
    }
    sb += "\n\n(Included \(included) of \(ranked.count) comments, highest-scored first.)"
    return (post, sb)
  }

  // MARK: AI

  /// One /v1/chat/completions call (AiService.summarize).
  private func chat(key: String, threadText: String) async throws -> String {
    let lang = settings.language.isEmpty
      ? "Write the summary in the same language as the thread."
      : "Write the summary in \(settings.language), whatever language the thread is in."
    let system = "You summarize Reddit threads accurately and neutrally. Do not invent "
      + "details. \(style.instruction) \(lang)"
    // A base documented with its version (…/openai/v1) gets no second /v1.
    var base = settings.baseUrl.trimmingCharacters(in: .whitespaces)
    while base.hasSuffix("/") { base.removeLast() }
    let versioned = base.range(of: #"/v\d+$"#, options: .regularExpression) != nil
    guard let url = URL(string: versioned ? "\(base)/chat/completions" : "\(base)/v1/chat/completions") else {
      throw SummaryError("The AI endpoint in Settings isn't a valid URL.")
    }
    var req = URLRequest(url: url, timeoutInterval: 90)
    req.httpMethod = "POST"
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": settings.model,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": threadText],
      ],
    ])
    let data: Data, res: URLResponse
    do {
      (data, res) = try await URLSession.shared.data(for: req)
    } catch {
      throw SummaryError("Could not reach the AI endpoint: \(error.localizedDescription)")
    }
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    let status = (res as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      let err = json?["error"]
      let msg = (err as? [String: Any])?["message"] as? String
        ?? (err as? String) ?? String(data: data, encoding: .utf8) ?? ""
      throw SummaryError("AI request failed (\(status)): \(msg)")
    }
    let content = (((json?["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any])?["content"] as? String
    let text = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if text.isEmpty { throw SummaryError("The AI returned an empty answer.") }
    return text
  }

  // MARK: You → Summaries

  /// Left in the shared keychain; the app adds it to Summaries when it next
  /// runs (app.dart). Same fields as SavedSummary.
  private static func keep(_ post: SharedPost, summary: String, style: SummaryStyle, model: String) {
    var list = SharedStore.read(SharedStore.pendingSummaries)
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
    list.removeAll { $0["postId"] as? String == post.id }
    list.append([
      "postId": post.id,
      "subreddit": post.subreddit,
      "title": post.title,
      "permalink": post.permalink,
      "style": style.label,
      "model": model,
      "text": summary,
      "createdAt": Int(Date().timeIntervalSince1970 * 1000),
    ])
    SharedStore.write(SharedStore.pendingSummaries, try? JSONSerialization.data(withJSONObject: list))
  }
}

// MARK: - The sheet

/// Ilay's violet.
private let accent = Color(red: 0x6E / 255, green: 0x52 / 255, blue: 0xD6 / 255)

private struct SummaryView: View {
  @ObservedObject var model: SummaryModel
  let close: () -> Void
  let open: (URL, Bool) -> Void
  @State private var copied = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles").foregroundStyle(accent)
        Text("AI summary · \(model.style.label)").font(.subheadline.weight(.bold))
        Spacer()
        if let text = model.text, !model.loading {
          Button {
            UIPasteboard.general.string = text
            copied = true
          } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
          }
          .accessibilityLabel("Copy")
        }
        Button(action: close) {
          Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Close")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .tint(accent)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let post = model.post {
            Text("r/\(post.subreddit) · \(post.title)")
              .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
          }
          if model.loading {
            VStack(spacing: 12) {
              ProgressView().tint(accent)
              Text(model.stage).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
          } else if let error = model.error {
            Text(error.errorDescription ?? "").foregroundStyle(.red)
            HStack {
              if error.openApp, let link = model.link {
                Button("Summarize in Ilay") { open(link, true) }.buttonStyle(.borderedProminent)
              } else {
                Button("Retry") { Task { await model.run() } }.buttonStyle(.borderedProminent)
              }
            }
            .tint(accent)
          } else if let text = model.text {
            MarkdownText(markdown: text).textSelection(.enabled)
            Text("Generated by \(model.settings.model). AI summaries can be wrong.")
              .font(.caption2).foregroundStyle(.secondary)
            if let post = model.post, let link = URL(string: "https://www.reddit.com\(post.permalink)") {
              Button("Open in Ilay") { open(link, false) }.tint(accent)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
      }
    }
    .background(Color(.systemBackground))
  }
}

/// The summary's markdown: headings, bullet and numbered lists (nested by
/// indent) and paragraphs, with inline bold / italic / links / code.
private struct MarkdownText: View {
  let markdown: String

  private enum Block {
    case heading(String), bullet(String, Int), numbered(String, String, Int), paragraph(String)
  }

  private var blocks: [Block] {
    markdown.components(separatedBy: "\n").compactMap { raw in
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { return nil }
      let level = (raw.prefix { $0 == " " }.count) / 2
      if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
        return .heading(String(line[m.upperBound...]))
      }
      if let m = line.range(of: #"^[-*•+]\s+"#, options: .regularExpression) {
        return .bullet(String(line[m.upperBound...]), level)
      }
      if let m = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
        return .numbered(String(line[..<m.upperBound]).trimmingCharacters(in: .whitespaces),
                         String(line[m.upperBound...]), level)
      }
      return .paragraph(line)
    }
  }

  private func inline(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(s)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        switch block {
        case .heading(let s):
          Text(inline(s)).font(.headline).padding(.top, 4)
        case .bullet(let s, let level):
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("•")
            Text(inline(s))
          }
          .padding(.leading, CGFloat(level) * 18)
        case .numbered(let n, let s, let level):
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n).monospacedDigit()
            Text(inline(s))
          }
          .padding(.leading, CGFloat(level) * 18)
        case .paragraph(let s):
          Text(inline(s))
        }
      }
    }
    .font(.body)
    .tint(accent)
  }
}
