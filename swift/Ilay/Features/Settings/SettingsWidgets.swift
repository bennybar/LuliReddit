import SwiftUI
import UniformTypeIdentifiers

/// A setting's title with its explanation under it.
struct SettingLabel: View {
    let title: String
    var subtitle: String? = nil
    var titleColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(titleColor ?? .primary)
            if let subtitle {
                // The colour, not the style: inside a Button the style would follow the tint.
                Text(subtitle).font(.footnote).foregroundStyle(Color.secondary)
            }
        }
    }
}

/// One choice in a picker page.
struct PickOption<T: Hashable> {
    let value: T
    let label: String
    var subtitle: String? = nil
    /// SF Symbol.
    var icon: String? = nil
}

/// A choice made on the page itself (Settings › Appearance, under its pinned preview):
/// a segmented control for up to four short options without icons, else a scrolling row
/// of capsules. Picking doesn't leave the page, so options can be tried one after another.
struct InlineChoice<T: Hashable>: View {
    let title: String
    var subtitle: String? = nil
    let value: T
    let options: [PickOption<T>]
    let set: (T) -> Void

    private var segmented: Bool {
        options.count <= 4 && options.allSatisfy { $0.icon == nil && $0.label.count <= 10 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingLabel(title: title, subtitle: subtitle)
            if segmented {
                Picker(title, selection: Binding(get: { value }, set: set)) {
                    ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(options, id: \.value) { option in
                            let on = option.value == value
                            Button { set(option.value) } label: {
                                Group {
                                    if let icon = option.icon { Label(option.label, systemImage: icon) } else { Text(option.label) }
                                }
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                // At least 44pt to tap.
                                .frame(minHeight: 44)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(on ? AnyShapeStyle(IlayTheme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(title): \(option.label)")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                // The capsules run to the row's edges as they scroll.
                .scrollClipDisabled()
            }
        }
        .padding(.vertical, 4)
    }
}

/// One row of the settings list. `search` = its title + subtitle, nil = not searchable.
struct SettingEntry: Identifiable {
    let id: String
    let section: String
    /// Splits a category's page into list sections (Kotlin's `divider`).
    let group: Int
    let title: String
    let search: String?
    let content: AnyView
}

/// What a text-entry prompt returned.
enum TextResult {
    case save(String)
    case remove
}

/// A single-field prompt. `secret` hides the text; `removable` adds "Remove".
struct TextPrompt {
    let title: String
    var hint = ""
    var note: String? = nil
    var secret = false
    var removable = false
    var keyboard: UIKeyboardType = .default
    let onDone: (TextResult) -> Void
}

/// The exported backup, for `fileExporter`.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// What the rows ask of their screen: prompts and the file panels, which SwiftUI
/// wants attached to a view.
@MainActor @Observable
final class SettingsPrompts {
    var text: TextPrompt?
    var input = ""
    var exporting: BackupDocument?
    var importing = false
    /// Bumped after a key changes (its row re-reads the key's state), and after a
    /// switch was refused (so it flips back).
    var refresh = 0

    func ask(_ prompt: TextPrompt, initial: String = "") {
        input = initial
        text = prompt
    }
}

/// A yes/no alert. True if confirmed.
@MainActor func confirmDialog(_ title: String, _ text: String, _ confirm: String, cancel: String = "Cancel", destructive: Bool = false) async -> Bool {
    await Overlays.alert(title, message: text, buttons: [
        (title: cancel, role: .cancel, value: false),
        (title: confirm, role: destructive ? .destructive : nil, value: true),
    ]) == true
}

/// An info alert with a single `close` button.
@MainActor func infoDialog(_ title: String, _ text: String, close: String = "Close") async {
    let _: Bool? = await Overlays.alert(title, message: text, buttons: [(title: close, role: .cancel, value: true)])
}

/// The subreddits hidden from the front page ("Hide r/… for 7 days"), each with Unhide.
private struct HiddenSubsSheet: View {
    var body: some View {
        let subs = app.hiddenHomeSubs.ids.sorted()
        NavigationStack {
            List {
                if subs.isEmpty {
                    Text("None. Hide one from a post's ⋯ menu or a swipe; it comes back after 7 days.")
                        .foregroundStyle(.secondary)
                }
                ForEach(subs, id: \.self) { sub in
                    HStack {
                        Text(subredditName(sub))
                        Spacer()
                        Button("Unhide") { app.hiddenHomeSubs.remove(sub) }.buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("Hidden subreddits")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor func showHiddenSubsSheet() {
    Overlays.launch(detents: [.medium, .large]) { _ in HiddenSubsSheet() }
}

/// Settings › Appearance's live preview: a window into the feed, not a shrunk card. The
/// sample post is drawn by the feed's own `PostCard` at true size, with the feed's insets
/// and spacing, on the feed's background, so every look option (layout, corners, text
/// sizes, theme, accent, icons, flair…) shows exactly as it will. In a group's Preview
/// sheet (#288); up to a third of the screen, a taller card fading out at the bottom with
/// its top always readable. The sample is local (a picture drawn here, no Reddit requests)
/// and inert.
///
/// `kind`: the post for the layout, colour and text options, a sample thread for the
/// comments' size.
struct AppearancePreview: View {
    var kind: PreviewKind = .post

    @State private var cardHeight: CGFloat = 0
    @State private var threadHeight: CGFloat = 0

    var body: some View {
        ZStack {
            switch kind {
            case .post: postStage
            case .comments: threadStage
            }
        }
        .frame(maxWidth: .infinity)
        // Look, don't touch: no votes, menus or opening the post.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .comments ? "Preview of comments with these settings" : "Preview of a post with these settings")
    }

    private var maxHeight: CGFloat {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? 874) * 0.34
    }

    private var postStage: some View {
        // The drawn picture back in the cache if it was let go (a file check otherwise).
        let _ = Self.photoData.map { ImageLoader.shared.seed($0, for: Self.photo) }
        // Read here (through `current`) so any appearance change redraws the card.
        let config = FeedRowConfig.current()
        let top: CGFloat = 8
        let background = Color(config.isCarded ? .systemGroupedBackground : .systemBackground)
        return PostCard(row: PostRow(Self.post, config: config))
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .padding(.top, top)
            .modifier(TrueSizeStage(height: cardHeight + top, maxHeight: maxHeight, background: background))
    }

    /// The thread's own rows, in its style (Calm or cards), at the comments' size.
    private var threadStage: some View {
        let background = Color(app.settings.value.calmComments ? .systemBackground : .systemGroupedBackground)
        return SampleCommentThread()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { threadHeight = $0 }
            .modifier(TrueSizeStage(height: threadHeight, maxHeight: maxHeight, background: background))
    }

    /// Where the drawn picture sits in the image cache: `.invalid` never resolves, so it's
    /// never really fetched; the body puts it back before the card asks for it.
    private static let photo = URL(string: "https://appearance-preview.invalid/photo.png")!

    /// A made-up post that shows most of a card: flair, a short body and a photo.
    private static let photoData = drawPhoto()

    private static let post: Post = {
        Post(
            id: "appearance_preview",
            fullname: "t3_appearance_preview",
            title: "Morning fog over the lake",
            subreddit: "photography",
            subredditPrefixed: "r/photography",
            author: "ilay_preview",
            score: 1234,
            numComments: 84,
            upvoteRatio: 0.97,
            createdUtc: Int(Date().timeIntervalSince1970 * 1000) - 2 * 3_600_000,
            permalink: "/r/photography/comments/appearance_preview/",
            url: photo.absoluteString,
            domain: "i.redd.it",
            type: .image,
            selftext: "Shot handheld at sunrise.",
            linkFlairText: "OC",
            linkFlair: UserFlair(parts: [FlairPart(text: "OC")]),
            previewUrl: photo.absoluteString,
            previewMedUrl: photo.absoluteString,
            // About 2.4:1, so the stage stays low: one line of title, one flair, one of body.
            previewWidth: 1200,
            previewHeight: 500
        )
    }()

    /// A small landscape: sky, sun, hills and a lake.
    private static func drawPhoto() -> Data? {
        let size = CGSize(width: 960, height: 540)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.98, green: 0.77, blue: 0.59, alpha: 1).cgColor,
                UIColor(red: 0.63, green: 0.61, blue: 0.75, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(red: 1, green: 0.93, blue: 0.75, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 620, y: 90, width: 120, height: 120))
            func fill(_ points: [CGPoint], _ color: UIColor) {
                color.setFill()
                c.beginPath()
                c.addLines(between: points)
                c.closePath()
                c.fillPath()
            }
            fill([.init(x: 0, y: 380), .init(x: 160, y: 220), .init(x: 300, y: 330), .init(x: 470, y: 170), .init(x: 650, y: 350),
                  .init(x: 790, y: 250), .init(x: 960, y: 360), .init(x: 960, y: 540), .init(x: 0, y: 540)],
                 UIColor(red: 0.45, green: 0.38, blue: 0.55, alpha: 1))
            fill([.init(x: 0, y: 430), .init(x: 220, y: 330), .init(x: 420, y: 410), .init(x: 600, y: 320), .init(x: 800, y: 400),
                  .init(x: 960, y: 350), .init(x: 960, y: 540), .init(x: 0, y: 540)],
                 UIColor(red: 0.31, green: 0.27, blue: 0.43, alpha: 1))
            UIColor(red: 0.38, green: 0.47, blue: 0.63, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 470, width: size.width, height: 70))
        }.pngData()
    }
}

/// A preview at true size, never scaled: a taller one is cut at `maxHeight` from the
/// bottom, fading into the stage there instead of a hard edge, its top always in full.
private struct TrueSizeStage: ViewModifier {
    let height: CGFloat
    let maxHeight: CGFloat
    let background: Color

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: height > 0 ? min(height, maxHeight) : nil, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                if height > maxHeight {
                    LinearGradient(colors: [background.opacity(0), background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                }
            }
            .background(background)
            .animation(.snappy, value: min(height, maxHeight))
    }
}

/// What an Appearance group's preview shows: what its options change.
enum PreviewKind: Equatable {
    case post, comments
}
