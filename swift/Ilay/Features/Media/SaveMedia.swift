import AVFoundation
import Photos
import SwiftUI

// Reddit's CDN (v.redd.it) closes the connection mid-stream for requests
// without a real User-Agent, so set one and allow a generous timeout.
private let downloadUA =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

private let downloadSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 90
    return URLSession(configuration: config)
}()

func mimeFor(_ ext: String, isVideo: Bool) -> String {
    switch ext {
    case "png": "image/png"
    case "gif": "image/gif"
    case "webp": "image/webp"
    case "jpg", "jpeg": "image/jpeg"
    case "mp4": "video/mp4"
    default: isVideo ? "video/mp4" : "image/jpeg"
    }
}

typealias DownloadProgress = @Sendable (_ received: Int64, _ total: Int64) -> Void

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let dest: URL
    let onProgress: DownloadProgress
    var continuation: CheckedContinuation<Void, Error>?
    private var lastEmit: Int64 = 0
    private var failure: Error?

    init(dest: URL, onProgress: @escaping DownloadProgress) {
        self.dest = dest
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData written: Int64, totalBytesWritten got: Int64, totalBytesExpectedToWrite expected: Int64) {
        let total = max(expected, 0)
        if got - lastEmit > 128 * 1024 || got == total {
            lastEmit = got
            onProgress(got, total)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            return
        }
        do {
            // Here or never: the system deletes the file when this returns.
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Cancelled: the closed connection's error is a cancellation.
        if (error as? URLError)?.code == .cancelled {
            continuation?.resume(throwing: CancellationError())
        } else if let problem = error ?? failure {
            continuation?.resume(throwing: problem)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

/// Downloads `url` into `dest`, reporting (received, total) every 128 KB. Cancelling the
/// caller aborts a blocked connect or read at once, not at the next chunk or the read
/// timeout, throwing `CancellationError`.
func downloadTo(_ url: String, dest: URL, onProgress: @escaping DownloadProgress = { _, _ in }) async throws {
    guard let parsed = URL(string: url) else { throw URLError(.badURL) }
    var request = URLRequest(url: parsed)
    request.setValue(downloadUA, forHTTPHeaderField: "User-Agent")
    let task = downloadSession.downloadTask(with: request)
    let delegate = DownloadDelegate(dest: dest, onProgress: onProgress)
    task.delegate = delegate
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            task.resume()
        }
    } onCancel: {
        task.cancel()
    }
}

private struct PhotosAccessDenied: LocalizedError {
    var errorDescription: String? { "Allow Ilay to access Photos in Settings." }
}

/// Asks for Photos only when the user first saves something. True: full access, so the
/// "Ilay" album is reachable; false: saving works but outside an album (limited access
/// can't touch albums, and add-only can't look one up). Throws when there's no access.
private func photosAccessForAlbum() async throws -> Bool {
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
    if status == .authorized { return true }
    if status == .limited || PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized { return false }
    throw PhotosAccessDenied()
}

/// Into the "Ilay" album, images and videos alike, as the Flutter build's gal plugin
/// saved them, so existing users keep one album. The file's own bytes go in: a GIF stays
/// animated.
private func insertIntoPhotos(_ file: URL, name: String, isVideo: Bool, toAlbum: Bool) async throws {
    var album: PHAssetCollection?
    if toAlbum {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", "Ilay")
        album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }
    try await PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = name
        request.addResource(with: isVideo ? .video : .photo, fileURL: file, options: options)
        guard toAlbum, let placeholder = request.placeholderForCreatedAsset else { return }
        let change = album.flatMap { PHAssetCollectionChangeRequest(for: $0) }
            ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Ilay")
        change.addAssets([placeholder] as NSArray)
    }
}

/// Downloads a media file to the "Ilay" album in Photos, with a cancellable progress
/// dialog showing downloaded / total size. Fetches `url` to a temp file named
/// `luli_<ts>`, first. Runs apart from the caller, so leaving the screen doesn't abort a
/// save; the dialog's Cancel does.
@MainActor func saveMedia(_ url: String, isVideo: Bool) async {
    let nav = app.navigator
    let toAlbum: Bool
    do {
        toAlbum = try await photosAccessForAlbum()
    } catch {
        nav.showSnackbar("Could not save: \(error.localizedDescription)")
        return
    }
    let progress = SavingProgress()
    let job = Task.detached { () -> String in
        let clean = url.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init) ?? url
        let last = clean.split(separator: "/").last.map(String.init) ?? ""
        var ext = last.contains(".") ? (last.split(separator: ".").last.map { $0.lowercased() } ?? "") : ""
        if ext.isEmpty || ext.count > 4 { ext = isVideo ? "mp4" : "jpg" }
        let name = "luli_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        let tmp = FileManager.default.temporaryDirectory.appending(path: name)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            // Reddit's own videos: with their sound (stored as a separate file).
            if isVideo, URL(string: url)?.host == "v.redd.it" {
                try await downloadRedditVideo(url, out: tmp, onProgress: progress.report)
            } else {
                try await downloadTo(url, dest: tmp, onProgress: progress.report)
            }
            try Task.checkCancellation()
            try await insertIntoPhotos(tmp, name: name, isVideo: isVideo, toAlbum: toAlbum)
            return "Saved to Photos"
        } catch is CancellationError {
            return "Download cancelled"
        } catch is URLError {
            return Task.isCancelled ? "Download cancelled" : "Could not save"
        } catch {
            return "Could not save: \(error.localizedDescription)"
        }
    }
    let dialog = SavingDialog.show(progress, verb: "Saving") { job.cancel() }
    let message = await job.value
    await dialog.close()
    nav.showSnackbar(message)
}

/// (received, total) of the running download, for its dialog.
@MainActor @Observable final class SavingProgress {
    private(set) var received: Int64 = 0
    private(set) var total: Int64 = 0

    nonisolated func report(_ received: Int64, _ total: Int64) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.received = received
                self.total = total
            }
        }
    }
}

private func mb(_ bytes: Int64) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }

/// The cancellable dialog of a save or a "Share as media" download. A small sheet over
/// whatever is on top, the viewer included; it can't be swiped away, only cancelled.
@MainActor final class SavingDialog {
    private let shown: Task<Void, Never>
    private weak var controller: UIViewController?

    private init(controller: UIViewController, over top: UIViewController) {
        self.controller = controller
        shown = Task { @MainActor in
            await withCheckedContinuation { done in top.present(controller, animated: true) { done.resume() } }
        }
    }

    static func show(_ progress: SavingProgress, verb: String, onCancel: @escaping () -> Void) -> SavingDialog {
        let sheet = UIHostingController(rootView: SavingDialogContent(progress: progress, verb: verb, onCancel: onCancel))
        sheet.isModalInPresentation = true
        sheet.sheetPresentationController?.detents = [.custom { _ in 150 }]
        return SavingDialog(controller: sheet, over: topViewController() ?? sheet)
    }

    /// Closes it, also if the work ended before it had finished opening.
    func close() async {
        await shown.value
        guard let controller, controller.presentingViewController != nil else { return }
        await withCheckedContinuation { done in controller.dismiss(animated: true) { done.resume() } }
    }
}

private struct SavingDialogContent: View {
    let progress: SavingProgress
    let verb: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(progress.total > 0 ? "\(verb)… \(mb(progress.received)) / \(mb(progress.total)) MB" : "\(verb)…")
                .font(.headline)
                .monospacedDigit()
            // Filling up when the size is known, travelling otherwise.
            if progress.total > 0 {
                ProgressView(value: min(max(Double(progress.received) / Double(progress.total), 0), 1))
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Button("Cancel", role: .cancel, action: onCancel)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
    }
}
