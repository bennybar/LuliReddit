import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// An image off the clipboard (a pasted screenshot/copy, or a GIF a keyboard copied:
/// iOS keyboards hand over media through the clipboard, unlike Android's content
/// receiver). The file as it is, so a GIF keeps moving. nil if there's no image.
@MainActor func pasteImageAttachment(from pasteboard: UIPasteboard = .general) -> MediaAttachment? {
    for (type, ext) in [(UTType.gif, "gif"), (.webP, "webp"), (.jpeg, "jpg"), (.png, "png")] {
        if let data = pasteboard.data(forPasteboardType: type.identifier), !data.isEmpty {
            return MediaAttachment(bytes: data, filename: "pasted.\(ext)", mimeType: type.preferredMIMEType ?? "image/\(ext)", isVideo: false)
        }
    }
    guard let png = pasteboard.image?.pngData() else { return nil }
    return MediaAttachment(bytes: png, filename: "pasted.png", mimeType: "image/png", isVideo: false)
}

/// Files are held in memory to upload, so one too big for that (a long phone video)
/// is refused with a clear message.
private let maxUploadBytes = 150 * 1024 * 1024

/// A picked video as a file (a copy in tmp, deleted by the reader), so a long one
/// isn't read into memory before its size is known.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            // The received file goes away when this returns.
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension.nilIfEmpty ?? "mov")")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// A picked image/video, read into memory. Reddit takes neither HEIC nor QuickTime's
/// container well, and those are what a phone's library holds: they go as JPEG and MP4.
func readPicked(_ item: PhotosPickerItem, isVideo: Bool) async throws -> MediaAttachment {
    let tooBig = { (bytes: Int) in
        AppException("This file is \(bytes / (1024 * 1024)) MB; the most Ilay can upload is \(maxUploadBytes / (1024 * 1024)) MB.")
    }
    let type = item.supportedContentTypes.first
    if isVideo {
        guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw AppException("Couldn't read the file.") }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        let size = (try? movie.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maxUploadBytes { throw tooBig(size) }
        let mp4 = type?.conforms(to: .mpeg4Movie) == true ? nil : await remuxToMp4(movie.url)
        defer { if let mp4 { try? FileManager.default.removeItem(at: mp4) } }
        return MediaAttachment(bytes: try Data(contentsOf: mp4 ?? movie.url), filename: "video.mp4", mimeType: "video/mp4", isVideo: true)
    }
    guard let data = try await item.loadTransferable(type: Data.self) else { throw AppException("Couldn't read the file.") }
    if data.count > maxUploadBytes { throw tooBig(data.count) }
    if type?.conforms(to: .heic) == true || type?.conforms(to: .heif) == true, let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
        return MediaAttachment(bytes: jpeg, filename: "image.jpg", mimeType: "image/jpeg", isVideo: false)
    }
    let ext = type?.preferredFilenameExtension ?? "jpg"
    return MediaAttachment(bytes: data, filename: "image.\(ext)", mimeType: type?.preferredMIMEType ?? "image/jpeg", isVideo: false)
}

/// The same samples in an MP4 file in tmp (no re-encode; the caller deletes it), or
/// nil if it can't be done.
private func remuxToMp4(_ input: URL) async -> URL? {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    guard let session = AVAssetExportSession(asset: AVURLAsset(url: input), presetName: AVAssetExportPresetPassthrough),
          (try? await session.export(to: output, as: .mp4)) != nil else {
        try? FileManager.default.removeItem(at: output)
        return nil
    }
    return output
}

/// A JPEG poster frame for a video (Reddit needs one for video posts). A video the
/// frame can't be read from gets a black one: never the video itself as "poster.jpg".
func posterFrame(_ video: Data) async -> Data {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: file) }
    if (try? video.write(to: file)) != nil {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        if let frame = try? await generator.image(at: .zero).image,
           let jpeg = UIImage(cgImage: frame).jpegData(compressionQuality: 0.75) { return jpeg }
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360), format: format).jpegData(withCompressionQuality: 0.75) { context in
        UIColor.black.setFill()
        context.fill(context.format.bounds)
    }
}

/// An image pasted with `PasteButton`, as its file so a GIF keeps moving. Unlike
/// reading `UIPasteboard`, the system Paste button doesn't make iOS ask "Allow Paste?".
struct PastedImage: Transferable {
    let media: MediaAttachment

    static var transferRepresentation: some TransferRepresentation {
        file(.gif, "gif")
        file(.webP, "webp")
        file(.jpeg, "jpg")
        file(.png, "png")
        // Anything else (HEIC, TIFF…) as PNG, as `pasteImageAttachment` does.
        DataRepresentation(importedContentType: .image) { data in
            guard let png = UIImage(data: data)?.pngData() else { throw AppException("No image on the clipboard.") }
            return PastedImage(media: MediaAttachment(bytes: png, filename: "pasted.png", mimeType: "image/png", isVideo: false))
        }
    }

    private static func file(_ type: UTType, _ ext: String) -> DataRepresentation<PastedImage> {
        DataRepresentation(importedContentType: type) { data in
            PastedImage(media: MediaAttachment(bytes: data, filename: "pasted.\(ext)", mimeType: type.preferredMIMEType ?? "image/\(ext)", isVideo: false))
        }
    }
}

/// A Markdown field that also takes images and GIFs through the system's Paste, as an
/// attachment, like one picked from the library (SwiftUI's `TextEditor` can't).
/// `MarkdownToolbar` works on it through the same `text` and `selection`.
struct MediaTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var placeholder = ""
    var minLines = 1
    var maxLines = 12
    /// Where a pasted image or GIF goes; nil: this field takes text only.
    var onMedia: ((MediaAttachment) -> Void)? = nil
    /// Opens the keyboard on it when shown (`.focused` doesn't reach a UIKit view).
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PastingTextView {
        let view = PastingTextView()
        view.delegate = context.coordinator
        view.focusOnAppear = focusOnAppear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.placeholderLabel.text = placeholder
        view.text = text
        view.placeholderLabel.isHidden = !text.isEmpty
        return view
    }

    func updateUIView(_ view: PastingTextView, context: Context) {
        context.coordinator.parent = self
        view.onMedia = onMedia
        view.placeholderLabel.text = placeholder
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if view.text != text {
            view.text = text
            view.placeholderLabel.isHidden = !text.isEmpty
        }
        if case .selection(let range)? = selection?.indices, range.upperBound <= text.endIndex {
            let start = range.lowerBound.utf16Offset(in: text)
            let wanted = NSRange(location: start, length: range.upperBound.utf16Offset(in: text) - start)
            if view.selectedRange != wanted { view.selectedRange = wanted }
        }
    }

    /// Grows with the text from `minLines` to `maxLines`, then scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: PastingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let line = view.font?.lineHeight ?? 20
        let fit = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let maxHeight = line * CGFloat(maxLines)
        let scrolls = fit > maxHeight
        if view.isScrollEnabled != scrolls { view.isScrollEnabled = scrolls }
        return CGSize(width: width, height: min(max(fit, line * CGFloat(minLines)), maxHeight))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MediaTextEditor
        var updating = false

        init(_ parent: MediaTextEditor) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            (view as? PastingTextView)?.placeholderLabel.isHidden = !view.text.isEmpty
            parent.text = view.text
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            if updating { return }
            let text = view.text ?? ""
            let range = view.selectedRange
            guard range.location != NSNotFound, range.location + range.length <= text.utf16.count else { return }
            let start = String.Index(utf16Offset: range.location, in: text)
            let end = String.Index(utf16Offset: range.location + range.length, in: text)
            parent.selection = start == end ? TextSelection(insertionPoint: start) : TextSelection(range: start..<end)
        }
    }
}

final class PastingTextView: UITextView {
    var onMedia: ((MediaAttachment) -> Void)?
    var focusOnAppear = false
    let placeholderLabel = UILabel()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if focusOnAppear, window != nil {
            focusOnAppear = false
            becomeFirstResponder()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Only asks whether there's an image, so no paste permission banner shows.
    private var clipboardHasImage: Bool {
        UIPasteboard.general.hasImages || UIPasteboard.general.contains(pasteboardTypes: [UTType.gif.identifier, UTType.webP.identifier])
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), onMedia != nil, clipboardHasImage { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if let onMedia, clipboardHasImage, let media = pasteImageAttachment() {
            onMedia(media)
        } else {
            super.paste(sender)
        }
    }
}
