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

/// A picked image/video, read into memory. Reddit takes neither HEIC nor QuickTime's
/// container well, and those are what a phone's library holds: they go as JPEG and MP4.
func readPicked(_ item: PhotosPickerItem, isVideo: Bool) async throws -> MediaAttachment {
    guard var data = try await item.loadTransferable(type: Data.self) else { throw AppException("Couldn't read the file.") }
    if data.count > maxUploadBytes {
        throw AppException("This file is \(data.count / (1024 * 1024)) MB; the most Ilay can upload is \(maxUploadBytes / (1024 * 1024)) MB.")
    }
    let type = item.supportedContentTypes.first
    if isVideo {
        if type?.conforms(to: .mpeg4Movie) != true, let mp4 = await remuxToMp4(data) { data = mp4 }
        return MediaAttachment(bytes: data, filename: "video.mp4", mimeType: "video/mp4", isVideo: true)
    }
    if type?.conforms(to: .heic) == true || type?.conforms(to: .heif) == true, let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
        return MediaAttachment(bytes: jpeg, filename: "image.jpg", mimeType: "image/jpeg", isVideo: false)
    }
    let ext = type?.preferredFilenameExtension ?? "jpg"
    return MediaAttachment(bytes: data, filename: "image.\(ext)", mimeType: type?.preferredMIMEType ?? "image/jpeg", isVideo: false)
}

/// The same samples in an MP4 (no re-encode), or nil if it can't be done.
private func remuxToMp4(_ data: Data) async -> Data? {
    let dir = FileManager.default.temporaryDirectory
    let input = dir.appendingPathComponent("\(UUID().uuidString).mov")
    let output = dir.appendingPathComponent("\(UUID().uuidString).mp4")
    defer {
        try? FileManager.default.removeItem(at: input)
        try? FileManager.default.removeItem(at: output)
    }
    guard (try? data.write(to: input)) != nil,
          let session = AVAssetExportSession(asset: AVURLAsset(url: input), presetName: AVAssetExportPresetPassthrough),
          (try? await session.export(to: output, as: .mp4)) != nil else { return nil }
    return try? Data(contentsOf: output)
}

/// A JPEG poster frame for a video (Reddit needs one for video posts).
func posterFrame(_ video: Data) async -> Data? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: file) }
    guard (try? video.write(to: file)) != nil else { return nil }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
    generator.appliesPreferredTrackTransform = true
    guard let frame = try? await generator.image(at: .zero).image else { return nil }
    return UIImage(cgImage: frame).jpegData(compressionQuality: 0.75)
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PastingTextView {
        let view = PastingTextView()
        view.delegate = context.coordinator
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
    let placeholderLabel = UILabel()

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
