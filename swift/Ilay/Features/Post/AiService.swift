import Foundation

/// Summary styles for AI thread summaries. Persisted by index (`aiSummaryStyle`).
enum SummaryStyle: Int, CaseIterable, Sendable {
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

/// One chat turn in "Ask about this thread".
struct AiMessage: Equatable, Sendable {
    let fromUser: Bool
    let text: String
}

/// Minimal client for an OpenAI-compatible /v1/chat/completions endpoint.
/// Works with OpenAI or any compatible gateway (e.g. LiteLLM) via baseUrl.
enum AiService {
    private static let client = URLSession(configuration: Http.configuration(timeout: 90))

    /// Returns the assistant's summary text, or throws with a readable message.
    static func summarize(baseUrl: String, apiKey: String, model: String, style: SummaryStyle, threadText: String, language: String = "") async throws -> String {
        // Settings → AI summaries → Summary language ("" = the thread's own).
        let lang = language.isEmpty ? "Write the summary in the same language as the thread."
            : "Write the summary in \(language), whatever language the thread is in."
        let system = "You summarize Reddit threads accurately and neutrally. Do not invent details. \(style.instruction) \(lang)"
        return try await chat(baseUrl: baseUrl, apiKey: apiKey, model: model, messages: [("system", system), ("user", threadText)])
    }

    /// Answers [question] about the thread in [threadText], continuing the
    /// conversation in [history] (alternating user / assistant turns, oldest
    /// first). Answers only from the thread, and says so when it can't tell.
    static func ask(baseUrl: String, apiKey: String, model: String, threadText: String, history: [AiMessage], question: String) async throws -> String {
        let system = "You answer questions about one Reddit thread: the post and its "
            + "comments, given in the first user message. Use only what the thread "
            + "says. If it doesn't answer the question, say so plainly instead of "
            + "guessing. When a point comes from a specific comment, cite it with "
            + "that comment's tag right after the point, like [c3] (several: [c3] [c7]); "
            + "don't write the tags any other way. Be concise and use markdown."
        var messages: [(String, String)] = [
            ("system", system),
            ("user", "THE THREAD:\n\(threadText)"),
            ("assistant", "Got it. Ask me anything about this thread."),
        ]
        for m in history { messages.append((m.fromUser ? "user" : "assistant", m.text)) }
        messages.append(("user", question))
        return try await chat(baseUrl: baseUrl, apiKey: apiKey, model: model, messages: messages)
    }

    /// [texts] translated into [language] (its English name), in order: the
    /// fallback for languages the phone can't translate (Translate.swift). Sent
    /// as JSON arrays, in batches so a long thread fits a reply.
    static func translate(baseUrl: String, apiKey: String, model: String, texts: [String], language: String) async throws -> [String] {
        let system = "Translate each string in the JSON array the user sends into \(language). Keep Markdown, "
            + "links, line breaks, u/ and r/ names as they are. Reply with only a JSON array of the "
            + "translations: the same number of strings, in the same order."
        var out: [String] = []
        out.reserveCapacity(texts.count)
        for batch in Translate.batches(texts, maxChars: 6_000, maxCount: 60) {
            let reply = try await chat(baseUrl: baseUrl, apiKey: apiKey, model: model, messages: [("system", system), ("user", JsonElement.strings(batch).encoded())])
            // Some models wrap it in a ```json fence.
            let json = reply.substringAfter("[", missing: "").substringBeforeLast("]", missing: "")
            guard let list = parseJsonOrNull("[\(json)]").arr(), list.count == batch.count else {
                throw AppException("The AI's translation didn't come back whole. Try again.")
            }
            out += list.map { $0.content() ?? "" }
        }
        return out
    }

    /// One /v1/chat/completions call; returns the reply text or throws with a readable message.
    private static func chat(baseUrl: String, apiKey: String, model: String, messages: [(String, String)]) async throws -> String {
        guard let url = URL(string: chatUrl(baseUrl)), url.host != nil else {
            throw AppException("Could not reach the AI endpoint: bad address \(baseUrl)")
        }
        let body: JsonElement = [
            "model": .string(model),
            "messages": .array(messages.map { ["role": .string($0.0), "content": .string($0.1)] }),
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.encoded().utf8)
        let res: (status: Int, body: Data, response: HTTPURLResponse)
        do {
            res = try await client.send(req)
        } catch let e as URLError {
            if e.code == .cancelled { throw e }
            throw AppException("Could not reach the AI endpoint: \(e.localizedDescription)")
        }
        let data = try? AppJson.parse(res.body)
        if res.status != 200 {
            let msg: String
            if let data, data.obj() != nil {
                let err = data["error"]
                msg = err["message"].str() ?? err?.content() ?? err?.encoded() ?? data.encoded()
            } else {
                msg = String(decoding: res.body, as: UTF8.self)
            }
            throw AppException("AI request failed (\(res.status)): \(msg)")
        }
        let content = data["choices"][0]["message"]["content"].content()
        guard let out = content?.trimmed.nilIfEmpty else { throw AppException("The AI returned an empty answer.") }
        return out
    }

    /// The thread for Ask: like [buildThreadText], but each comment is tagged
    /// [c1], [c2]… so answers can cite them, plus [refs] (tag → comment) to turn
    /// those citations into links, and how many comments went in.
    struct CitedThread: Sendable {
        let text: String
        let refs: OrderedMap<Comment>
        let included: Int
        let loaded: Int
    }

    private static func header(_ post: Post) -> String {
        var s = "POST in r/\(post.subreddit) by u/\(post.author) — score \(post.score), \(post.numComments) comments\n"
        s += "TITLE: \(post.title)\n"
        if post.isSelf, !post.selftext.isBlank { s += "BODY: \(post.selftext.trimmed)\n" }
        return s
    }

    private static func ranked(_ comments: [Comment]) -> [Comment] {
        comments.filter { !$0.isMore && !$0.body.isBlank }.sorted { $0.score > $1.score }
    }

    private static func oneLine(_ body: String) -> String { body.replacingOccurrences(of: "\n", with: " ").trimmed }

    static func buildCitedThread(_ post: Post, _ comments: [Comment], maxChars: Int) -> CitedThread {
        var sb = header(post) + "\nTOP COMMENTS (most upvoted first), each with its tag:\n"
        var length = sb.length
        let rank = ranked(comments)
        var refs = OrderedMap<Comment>()
        for c in rank {
            let tag = "c\(refs.count + 1)"
            let line = "\n[\(tag)] [\(c.score)] u/\(c.author): \(oneLine(c.body))"
            length += line.length
            if length > maxChars { break }
            sb += line
            refs[tag] = c
        }
        sb += "\n\n(Included \(refs.count) of \(rank.count) comments, highest-scored first.)"
        return CitedThread(text: sb, refs: refs, included: refs.count, loaded: rank.count)
    }

    private static let citation = Re(#"\[(c\d+)]"#)

    /// Turns the answer's [c12] citations into links to those comments (`ilay-comment:<fullname>`).
    static func linkCitations(_ answer: String, _ refs: OrderedMap<Comment>) -> String {
        citation.replace(answer) { m in
            guard let c = refs[m.groups[1]] else { return "" }
            return "[u/\(c.author)](\(commentLink)\(c.fullname))"
        }
    }

    static let commentLink = "ilay-comment:"

    /// Builds the thread text to summarize: the post, then comments ordered by
    /// score (most upvoted first) until [maxChars] is reached.
    static func buildThreadText(_ post: Post, _ comments: [Comment], maxChars: Int) -> String {
        var sb = header(post) + "\nTOP COMMENTS (most upvoted first):\n"
        var length = sb.length
        let rank = ranked(comments)
        var included = 0
        for c in rank {
            let line = "\n[\(c.score)] u/\(c.author): \(oneLine(c.body))"
            length += line.length
            if length > maxChars { break }
            sb += line
            included += 1
        }
        sb += "\n\n(Included \(included) of \(rank.count) comments, highest-scored first.)"
        return sb
    }
}

private let trailingSlashes = Re("/+$")
private let versionEnd = Re(#"/v\d+$"#)

/// The chat endpoint under [baseUrl]. Providers document their base either
/// without the version (api.openai.com, a LiteLLM host) or with it
/// (api.groq.com/openai/v1): don't add a second /v1.
func chatUrl(_ baseUrl: String) -> String {
    let base = trailingSlashes.replace(baseUrl.trimmed, with: "")
    return versionEnd.contains(base) ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
}
