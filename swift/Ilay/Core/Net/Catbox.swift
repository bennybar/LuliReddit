import Foundation

/// Uploads bytes to catbox.moe — a free, anonymous file host (no account / API
/// key) that accepts images and video. Returns the public direct URL.
///
/// Used for media Reddit can't host natively: videos in comment replies and
/// any attachment in a private message. Anyone with the (unguessable) URL can
/// reach the file — surface that before uploading.
func uploadToCatbox(_ bytes: Data, filename: String) async throws -> String {
    var form = MultipartForm()
    form.add(name: "reqtype", value: "fileupload")
    form.add(name: "fileToUpload", filename: filename, data: bytes)
    var req = URLRequest(url: URL(string: "https://catbox.moe/user/api.php")!)
    req.httpMethod = "POST"
    req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
    req.httpBody = form.finished()
    let text = String(decoding: try await Http.session.send(req).body, as: UTF8.self).trimmed
    if !text.hasPrefix("http") { throw AppException("Upload failed: \(text.nilIfEmpty ?? "empty response")") }
    return text
}
