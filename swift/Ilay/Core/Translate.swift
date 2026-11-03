import Foundation
import NaturalLanguage
import SwiftUI
import Translation

/// Translation into the phone's language and Settings → Second language.
/// On the phone first, through Apple's Translation framework: free, private and
/// offline once a language is downloaded, which iOS asks for the first time.
/// Languages it can't do (Hebrew) go to Settings → Translation service: the
/// OpenAI key summaries use, or Azure Translator.
enum Translate {
    /// A language code as everywhere else (Java still says "iw" for Hebrew, "in" for Indonesian).
    static func norm(_ code: String) -> String {
        switch code {
        case "iw": return "he"
        case "in": return "id"
        case "ji": return "yi"
        default: return code
        }
    }

    /// The phone's language: the first thing posts are translated into.
    /// From the preferred list: Locale.current follows the app's own localizations.
    static var primary: String {
        let first = Locale.preferredLanguages.first ?? "en"
        return norm(Locale(identifier: first).language.languageCode?.identifier ?? "en")
    }

    /// [code]'s name in the phone's language ("German").
    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        return locale.localizedString(forLanguageCode: code) ?? code
    }

    /// The languages text in [from] can be translated into here: the phone's
    /// and the second language, minus [from], each when the phone or the
    /// translation service can do it.
    @MainActor
    static func targets(from: String) async -> [String] {
        let fallback = await fallbackReady()
        var out: [String] = []
        for to in [primary, app.settings.value.translateSecondLanguage].uniqued() where !to.isEmpty && to != from {
            if fallback { out.append(to) } else if await canTranslateOnPhone(from: from, to: to) { out.append(to) }
        }
        return out
    }

    @MainActor
    private static func fallbackReady() async -> Bool {
        if app.settings.value.translateService == "azure" {
            return await app.secureStore.azureTranslatorKey()?.isEmpty == false
        }
        return await app.secureStore.openaiKey()?.isEmpty == false
    }

    /// Whether the phone can translate [from] into [to] (now, or after a download).
    private static func canTranslateOnPhone(from: String, to: String) async -> Bool {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: from), to: Locale.Language(identifier: to))
        return status != .unsupported
    }

    /// The language [text] is in (a code like "de"), when the phone is fairly sure.
    static func detect(_ text: String) -> String? {
        if text.isBlank { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        // Scores run low on short text ("de" 0.33 vs "en" 0.24 on a title):
        // take the best guess when it clearly leads.
        let guesses = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        guard let best = guesses.first, best.value >= 0.25,
              best.value > (guesses.dropFirst().first?.value ?? 0) + 0.05 else { return nil }
        return norm(best.key.rawValue)
    }

    /// [texts] from [from] into [to], in order: on the phone when it can, else
    /// (or when that fails, or the download was declined) through the
    /// translation service. Nil when neither could; the service's error is thrown.
    @MainActor
    static func translate(_ texts: [String], from: String, to: String) async throws -> [String]? {
        if texts.isEmpty { return [] }
        if await canTranslateOnPhone(from: from, to: to), let out = await onPhone(texts, from: from, to: to) { return out }
        if await !fallbackReady() { return nil }
        let s = app.settings.value
        if s.translateService == "azure" {
            return try await azure(texts, from: from, to: to, key: await app.secureStore.azureTranslatorKey()!, region: s.azureRegion)
        }
        let base = s.aiUseCustomUrl ? s.aiBaseUrl : "https://api.openai.com"
        let english = Locale(identifier: "en").localizedString(forLanguageCode: to) ?? to
        return try await AiService.translate(baseUrl: base, apiKey: await app.secureStore.openaiKey()!, model: s.aiModel, texts: texts, language: english)
    }

    /// [texts] translated in order, or nil. A language not downloaded yet goes
    /// through the system's download prompt, which needs a view: a clear one
    /// shown over Ilay while it works.
    @MainActor
    private static func onPhone(_ texts: [String], from: String, to: String) async -> [String]? {
        let source = Locale.Language(identifier: from)
        let target = Locale.Language(identifier: to)
        func run(_ session: TranslationSession) async -> [String]? {
            // One request for a whole thread's comments.
            let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: "\($0)") }
            guard let responses = try? await session.translations(from: requests) else { return nil }
            var out = texts
            for r in responses {
                if let i = Int(r.clientIdentifier ?? "") { out[i] = r.targetText }
            }
            return out
        }
        if await LanguageAvailability().status(from: source, to: target) == .installed {
            return await run(TranslationSession(installedSource: source, target: target))
        }
        guard let top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
        else { return nil }
        var presenter = top
        while let next = presenter.presentedViewController { presenter = next }
        return await withCheckedContinuation { cont in
            let host = UIHostingController(rootView: TranslateHost(
                config: .init(source: source, target: target),
                work: { session in
                    let out = await run(session)
                    presenter.dismiss(animated: false)
                    cont.resume(returning: out)
                }
            ))
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            presenter.present(host, animated: false)
        }
    }

    /// Azure Translator (Settings → Translation service): [key] and the
    /// resource's [region] (empty for a global resource). Up to 1000 texts
    /// and 50k characters a request, so a big thread goes in batches.
    private static func azure(_ texts: [String], from: String, to: String, key: String, region: String) async throws -> [String] {
        var out: [String] = []
        for batch in batches(texts, maxChars: 40_000, maxCount: 900) {
            var c = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
            c.queryItems = [
                URLQueryItem(name: "api-version", value: "3.0"),
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to),
            ]
            var req = URLRequest(url: c.url!)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            if !region.isEmpty { req.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region") }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(JsonElement.array(batch.map { ["Text": .string($0)] }).encoded().utf8)
            let res: (status: Int, body: Data, response: HTTPURLResponse)
            do {
                res = try await Http.session.send(req)
            } catch is URLError {
                throw AppException("Couldn't reach Azure Translator: \(req.url?.host ?? "")")
            }
            let json = try? AppJson.parse(res.body)
            if res.status != 200 {
                let text = String(decoding: res.body, as: UTF8.self)
                throw AppException("Azure Translator refused it (\(res.status)): \(json["error"]["message"].str() ?? text)")
            }
            for (i, t) in batch.enumerated() { out.append(json[i]["translations"][0]["text"].str() ?? t) }
        }
        return out
    }

    /// [texts] in order, in groups of at most [maxChars] characters and [maxCount] texts.
    static func batches(_ texts: [String], maxChars: Int, maxCount: Int) -> [[String]] {
        var out: [[String]] = []
        var chars = 0
        for t in texts {
            if let last = out.last, last.count < maxCount, chars + t.length <= maxChars {
                out[out.count - 1].append(t)
                chars += t.length
            } else {
                out.append([t])
                chars = t.length
            }
        }
        return out
    }
}

/// Runs [work] with a translation session from SwiftUI's translationTask,
/// which asks to download the language first when it isn't on the phone.
private struct TranslateHost: View {
    let config: TranslationSession.Configuration
    let work: (TranslationSession) async -> Void

    var body: some View {
        Color.clear.translationTask(config) { session in await work(session) }
    }
}
