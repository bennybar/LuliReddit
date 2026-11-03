import Foundation

/// The one shared URLSession for Reddit, so every request reuses warm
/// connections. No HTTP cache and no cookie jar: cookies are sent by hand (one
/// account's must never leak into another's requests), the response cache
/// lives in ResponseCache.
enum Http {
    static func configuration(timeout: TimeInterval = 30) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = timeout
        c.httpMaximumConnectionsPerHost = 16
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        return c
    }

    static let session = URLSession(configuration: configuration())

    /// Answers a redirect with the redirect itself (share links).
    static let noRedirects = URLSession(configuration: configuration(), delegate: NoRedirects(), delegateQueue: nil)

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? { nil }
    }
}

extension URLSession {
    /// The status code and body of [request].
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data, response: HTTPURLResponse) {
        let (data, res) = try await data(for: request)
        guard let http = res as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (http.statusCode, data, http)
    }
}

/// A `multipart/form-data` body (uploads to Reddit's media store and Catbox).
struct MultipartForm {
    let boundary = "ilay-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(name: String, value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func add(name: String, filename: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finished() -> Data { body + Data("--\(boundary)--\r\n".utf8) }
}

/// [request]'s body as URL-encoded form fields, nil values left out.
func formEncoded(_ fields: [(String, String?)]) -> Data {
    // Unreserved characters stay; a space goes as "+", which is why "+" itself can't stay.
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._*")
    allowed.insert(" ")
    let pairs = fields.compactMap { k, v -> String? in
        guard let v else { return nil }
        func enc(_ s: String) -> String {
            (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: " ", with: "+")
        }
        return "\(enc(k))=\(enc(v))"
    }
    return Data(pairs.joined(separator: "&").utf8)
}
