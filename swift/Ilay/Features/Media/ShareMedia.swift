import AVFoundation
import UIKit

/// Shared files are kept this long (the receiving app reads them after the share sheet closes), then deleted.
private let keepSeconds: TimeInterval = 30 * 60

/// Image, GIF, gallery and Reddit / Redgifs video posts: the ones "Share as media" can download.
func canShareAsMedia(_ p: Post) -> Bool {
    switch p.type {
    case .image, .gif: true
    case .gallery: !p.gallery.isEmpty
    case .video: !isExternalVideo(p) && (p.fallbackVideoUrl != nil || Redgifs.id(p.url) != nil)
    default: false
    }
}

/// The system share sheet over whatever is on top, the viewers included.
@MainActor func presentShareSheet(items: [Any]) {
    guard let top = topViewController() else { return }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    // Anchors the popover where there is one (iPad).
    sheet.popoverPresentationController?.sourceView = top.view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
    sheet.popoverPresentationController?.permittedArrowDirections = []
    top.present(sheet, animated: true)
}

/// "Share as media": downloads the post's image(s) or video and hands the files
/// themselves to the share sheet, rather than a link. They live in the app's temporary
/// folder only until shared: deleted `keepSeconds` later (or at the next share, if the
/// app was closed meanwhile).
@MainActor func shareAsMedia(_ post: Post) {
    let nav = app.navigator
    let progress = SavingProgress()
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "share_media")
    let dir = root.appending(path: "\(Int(Date().timeIntervalSince1970 * 1000))")

    let job = Task.detached { () -> [URL] in
        // Anything left over from shares older than keepSeconds.
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        for old in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? [] {
            let modified = (try? old.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > keepSeconds { try? fm.removeItem(at: old) }
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = try await downloadPostMedia(post, dir: dir, onProgress: progress.report)
        if files.isEmpty { throw URLError(.resourceUnavailable) }
        return files
    }
    let dialog = SavingDialog.show(progress, verb: "Downloading") { job.cancel() }
    Task { @MainActor in
        do {
            let files = try await job.value
            await dialog.close()
            presentShareSheet(items: files)
            Task.detached {
                try? await Task.sleep(for: .seconds(keepSeconds))
                try? fm.removeItem(at: dir)
            }
        } catch {
            try? fm.removeItem(at: dir)
            await dialog.close()
            nav.showSnackbar(error is CancellationError || job.isCancelled ? "Share cancelled" : "Couldn't download the media to share")
        }
    }
}

/// Downloads `post`'s media into `dir`: one file, or one per gallery image.
private func downloadPostMedia(_ post: Post, dir: URL, onProgress: @escaping DownloadProgress) async throws -> [URL] {
    func target(_ url: String, fallbackExt: String, _ i: Int = 0) -> URL {
        let path = url.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init) ?? url
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        let found = name.contains(".") ? (name.split(separator: ".").last?.lowercased() ?? "") : ""
        let ext = (3...4).contains(found.count) ? found : fallbackExt
        return dir.appending(path: "ilay_\(post.id)\(i > 0 ? "_\(i)" : "").\(ext)")
    }
    func image(_ url: String, _ i: Int = 0) async throws -> URL {
        let file = target(url, fallbackExt: "jpg", i)
        try await downloadTo(url, dest: file, onProgress: onProgress)
        return file
    }

    switch post.type {
    case .image:
        let isImage = URL(string: post.url).map(isImageUrl) ?? false
        return [try await image(isImage ? post.url : post.previewUrl ?? post.url)]
    case .gif:
        // Reddit's mp4 version of a GIF is a fraction of the size; apps play it like a GIF.
        if let mp4 = post.gifMp4Url {
            let file = target(mp4, fallbackExt: "mp4")
            try await downloadTo(mp4, dest: file, onProgress: onProgress)
            return [file]
        }
        return [try await image(post.url)]
    case .gallery:
        var files: [URL] = []
        for (i, g) in post.gallery.enumerated() { files.append(try await image(g.url, i)) }
        return files
    case .video:
        let redgifs = post.fallbackVideoUrl == nil && Redgifs.id(post.url) != nil ? await Redgifs.shared.resolve(post.url) : nil
        guard let video = redgifs ?? post.fallbackVideoUrl else { return [] }
        let out = dir.appending(path: "ilay_\(post.id).mp4")
        if redgifs != nil {
            try await downloadTo(video, dest: out, onProgress: onProgress)
        } else {
            try await downloadRedditVideo(video, out: out, onProgress: onProgress)
        }
        return [out]
    default:
        return []
    }
}

/// Downloads a Reddit-hosted video (v.redd.it) into `out` *with its sound*: a Reddit
/// video's mp4 has none, the audio (if the video has any) is a separate file named in
/// its DASH playlist (DASH_AUDIO_128.mp4, CMAF_AUDIO_128.mp4…). Both are downloaded next
/// to `out` and put together, without re-encoding.
func downloadRedditVideo(_ videoUrl: String, out: URL, onProgress: @escaping DownloadProgress) async throws {
    let fm = FileManager.default
    let dir = out.deletingLastPathComponent()
    let stamp = UInt64(Date().timeIntervalSince1970 * 1_000_000)
    let silent = dir.appending(path: "video_\(stamp).mp4")
    let audio = dir.appending(path: "audio_\(stamp).mp4")
    let mpd = dir.appending(path: "playlist_\(stamp).mpd")
    defer {
        try? fm.removeItem(at: silent)
        try? fm.removeItem(at: audio)
        try? fm.removeItem(at: mpd)
    }
    try await downloadTo(videoUrl, dest: silent, onProgress: onProgress)
    let clean = videoUrl.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init) ?? videoUrl
    let base = clean.lastIndex(of: "/").map { String(clean[..<$0]) } ?? clean
    var audioName: String?
    do {
        try await downloadTo("\(base)/DASHPlaylist.mpd", dest: mpd)
        audioName = audioTrack((try? String(contentsOf: mpd, encoding: .utf8)) ?? "")
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        // No playlist: no sound.
    }
    var gotAudio = false
    if let audioName {
        do {
            try await downloadTo("\(base)/\(audioName)", dest: audio, onProgress: onProgress)
            gotAudio = true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Keep the silent video.
        }
    }
    if gotAudio, (try? await mux(video: silent, audio: audio, out: out)) != nil, fm.fileExists(atPath: out.path) { return }
    try? fm.removeItem(at: out)
    try fm.copyItem(at: silent, to: out) // No sound (a silent clip): the video as is.
}

/// The best audio file named in a DASH playlist, or nil when the video has no sound.
func audioTrack(_ mpd: String) -> String? {
    let sets = try! NSRegularExpression(pattern: #"<AdaptationSet\b[^>]*>.*?</AdaptationSet>"#, options: .dotMatchesLineSeparators)
    let representation = try! NSRegularExpression(
        pattern: #"<Representation\b[^>]*?bandwidth="(\d+)"[^>]*>.*?<BaseURL>([^<]+)</BaseURL>"#,
        options: .dotMatchesLineSeparators
    )
    let text = mpd as NSString
    var best = -1
    var name: String?
    for match in sets.matches(in: mpd, range: NSRange(location: 0, length: text.length)) {
        let set = text.substring(with: match.range)
        guard set.contains(#"contentType="audio""#) || set.contains(#"mimeType="audio/"#) else { continue }
        let setText = set as NSString
        for rep in representation.matches(in: set, range: NSRange(location: 0, length: setText.length)) {
            let bandwidth = Int(setText.substring(with: rep.range(at: 1))) ?? 0
            if bandwidth > best {
                best = bandwidth
                name = setText.substring(with: rep.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    return name
}

private struct MuxError: Error {}

/// Puts `video`'s picture and `audio`'s sound into one mp4, copying the samples as they are.
private func mux(video: URL, audio: URL, out: URL) async throws {
    let v = AVURLAsset(url: video)
    let a = AVURLAsset(url: audio)
    guard let videoTrack = try await v.loadTracks(withMediaType: .video).first,
          let audioTrack = try await a.loadTracks(withMediaType: .audio).first
    else { throw MuxError() }
    let duration = try await v.load(.duration)
    let audioDuration = try await a.load(.duration)
    let composition = AVMutableComposition()
    let cv = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    let ca = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    try cv?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
    cv?.preferredTransform = try await videoTrack.load(.preferredTransform)
    try ca?.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero)
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw MuxError() }
    try? FileManager.default.removeItem(at: out)
    try await export.export(to: out, as: .mp4)
}
