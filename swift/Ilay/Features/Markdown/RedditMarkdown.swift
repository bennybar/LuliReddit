import SwiftUI

/// Reddit-flavoured markdown: paragraphs, headings, lists, quotes (accent bar),
/// code, tables, links (`app.navigator.openLink` by default), `>!spoilers!<` (tap to
/// reveal), `^superscript` / `^(words)`, strikethrough.
///
/// Parsing is cached (`RedditMarkdownParser.parse`); inline text is built into one
/// `AttributedString` per paragraph, so links and spoilers don't break the line, and
/// a plain paragraph is just `Text(verbatim:)`: most comments are one of those.
///
/// `media`: `media_metadata` id → URL (`Comment.media`), for `![gif](giphy|…)` and
/// `![img](id)` refs left in the text.
struct RedditMarkdown: View {
    let text: String
    var media: [String: String] = [:]
    var fontSize: CGFloat = 15
    var color: Color? = nil
    /// One text block, ellipsized (previews). Blocks flatten into lines.
    var maxLines: Int? = nil
    var selectable = false
    var onLinkClick: ((String) -> Void)? = nil

    /// Follows Dynamic Type, which `Settings.textScale` drives (see `ilayTheme`).
    @ScaledMetric(relativeTo: .body) private var dynamicScale: CGFloat = 1
    // Cells are reused: both are kept with the text they belong to, and a new text
    // ignores them (Kotlin's `remember(text)`).
    @State private var revealed: (text: String, spoilers: Set<Int>) = ("", [])
    @State private var parsedLate: (text: String, doc: MdDocument)?

    /// Up to here a parse takes a fraction of a frame (see the performance test), so a
    /// missed cache is parsed right here: the cell gets its real height on its first
    /// pass, instead of a jump. Longer bodies are parsed off the main actor.
    private static let parseInlineLimit = 4096

    private var document: MdDocument? {
        if let parsedLate, parsedLate.text == text { return parsedLate.doc }
        if let hit = RedditMarkdownParser.cached(text) { return hit }
        return text.utf8.count <= Self.parseInlineLimit ? RedditMarkdownParser.parse(text) : nil
    }

    var body: some View {
        if selectable {
            styled.textSelection(.enabled)
        } else {
            styled
        }
    }

    private var styled: some View {
        let size = fontSize * dynamicScale
        return Group {
            if let doc = document {
                content(doc, size: size)
            } else {
                // A long body's first frame: its raw text, about the right height.
                Text(verbatim: text)
                    .lineLimit(maxLines)
                    .task(id: text) {
                        let text = text
                        let doc = await Task.detached(priority: .userInitiated) { RedditMarkdownParser.parse(text) }.value
                        parsedLate = (text, doc)
                    }
            }
        }
        .font(.system(size: size))
        .lineSpacing(size * MdMetrics.lineSpacing)
        .foregroundColor(color)
        .environment(\.openURL, OpenURLAction { url in
            guard let action = MdAction(url) else { return .systemAction }
            switch action {
            case .link(let href):
                if let onLinkClick { onLinkClick(href) } else { app.navigator.openLink(href) }
            case .reveal(let index):
                let current = revealed.text == text ? revealed.spoilers : []
                revealed = (text, current.union([index]))
            }
            return .handled
        })
    }

    @ViewBuilder private func content(_ doc: MdDocument, size: CGFloat) -> some View {
        let context = MdContext(size: size, media: media, revealed: revealed.text == text ? revealed.spoilers : [])
        if let maxLines {
            // Previews: one text block, ellipsized.
            context.text(flattenInlines(doc.blocks))
                .lineLimit(maxLines)
                .truncationMode(.tail)
        } else if doc.isRtl {
            // Hebrew / Arabic / Persian text reads from the right: lay the blocks out
            // right-to-left (alignment, list bullets, quote bar), not just the glyphs.
            // Full width, so the text can sit against the right edge.
            MdBlocks(blocks: doc.blocks, context: context)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            MdBlocks(blocks: doc.blocks, context: context)
        }
    }
}

private enum MdMetrics {
    /// Kotlin's 1.45em line height, on top of SF's own (about 1.2em).
    static let lineSpacing: CGFloat = 0.25
    /// Reddit's `# … ######` over the 15pt body, as Kotlin's type scale gives them.
    static let headingScale: [CGFloat] = [1.6, 1.47, 1.07, 1.07, 1.07, 1.07]
    static let codeBackground = Color(uiColor: .tertiarySystemFill)
    /// Opaque: with a translucent colour the text would show through its own background.
    static let spoilerHidden = Color(uiColor: .systemGray)
    static let spoilerRevealed = Color(uiColor: .tertiarySystemFill)
    /// Downsample size of inline images: the widest iPhone screen, in pixels.
    static let imagePixels = 1320
}

/// What a tap on a run means, carried in its link. A real destination can be
/// anything (malformed links are common) and `URL` wouldn't take it, so it travels
/// percent-encoded in our own scheme and the caller gets the text as written.
private enum MdAction {
    case link(String)
    case reveal(Int)

    private static let scheme = "ilaymd"

    var url: URL? {
        switch self {
        case .link(let href):
            let encoded = href.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return URL(string: "\(Self.scheme)://link?\(encoded)")
        case .reveal(let index):
            return URL(string: "\(Self.scheme)://spoiler?\(index)")
        }
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme, let query = url.query(percentEncoded: true) else { return nil }
        if url.host == "spoiler" {
            guard let index = Int(query) else { return nil }
            self = .reveal(index)
        } else {
            self = .link(query.removingPercentEncoding ?? query)
        }
    }
}

private struct MdContext {
    let size: CGFloat
    let media: [String: String]
    let revealed: Set<Int>

    /// `size`/`weight` are set for a run only where they differ from the view's font,
    /// which keeps a plain run's attributes empty.
    func text(_ inlines: [MdInline], size runSize: CGFloat? = nil, weight: Font.Weight? = nil) -> Text {
        if inlines.count == 1, runSize == nil, weight == nil, let only = inlines.first,
           only.style.isEmpty, only.link == nil, only.spoiler < 0 {
            return Text(verbatim: only.text)
        }
        let base = runSize ?? size
        var out = AttributedString()
        for r in inlines {
            var run = AttributedString(r.text)
            if !r.style.isEmpty || runSize != nil || weight != nil {
                let scale: CGFloat = r.has(.sup) ? 0.75 : r.has(.code) ? 0.9 : 1
                var font = Font.system(
                    size: base * scale,
                    weight: r.has(.bold) ? .bold : weight ?? .regular,
                    design: r.has(.code) ? .monospaced : .default
                )
                if r.has(.italic) { font = font.italic() }
                run.font = font
                if r.has(.strike) { run.strikethroughStyle = .single }
                if r.has(.code) { run.backgroundColor = MdMetrics.codeBackground }
                if r.has(.sup) { run.baselineOffset = base * 0.35 }
            }
            if r.spoiler >= 0, !revealed.contains(r.spoiler) {
                // Same colour for text and background: a solid block until tapped.
                run.foregroundColor = MdMetrics.spoilerHidden
                run.backgroundColor = MdMetrics.spoilerHidden
                run.link = MdAction.reveal(r.spoiler).url
            } else {
                if r.spoiler >= 0 { run.backgroundColor = MdMetrics.spoilerRevealed }
                if let href = r.link { run.link = MdAction.link(href).url }
            }
            out.append(run)
        }
        return Text(out)
    }

    /// A ref from `media_metadata`, or a picker GIF Reddit sent with no URL.
    func imageURL(_ ref: String) -> URL? {
        if ref.hasPrefix("http") { return URL(string: ref) }
        return (media[ref] ?? giphyUrl(ref)).flatMap(URL.init(string:))
    }
}

private struct MdBlocks: View {
    let blocks: [MdBlock]
    let context: MdContext

    var body: some View {
        // The usual comment: one block, no stack around it.
        if blocks.count == 1 {
            MdBlockView(block: blocks[0], context: context)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks.indices, id: \.self) { MdBlockView(block: blocks[$0], context: context) }
            }
        }
    }
}

private struct MdBlockView: View {
    let block: MdBlock
    let context: MdContext

    var body: some View {
        switch block {
        case .paragraph(let inlines):
            context.text(inlines)
        case .heading(let level, let inlines):
            let size = context.size * MdMetrics.headingScale[min(max(level - 1, 0), 5)]
            context.text(inlines, size: size, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
        case .quote(let blocks):
            // Reddit-style blockquote: leading accent bar + subtle background,
            // readable text (the old light-blue box was low-contrast in dark mode).
            MdBlocks(blocks: blocks, context: context)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MdMetrics.codeBackground)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.tint).frame(width: 3)
                }
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: ordered ? "\(start + i)." : "•")
                            .frame(minWidth: 22, alignment: .trailing)
                        MdBlocks(blocks: items[i], context: context)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .code(let code):
            // Code reads left to right, whatever the language around it.
            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.system(size: context.size * 0.9, design: .monospaced))
                    .fixedSize()
                    .padding(8)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MdMetrics.codeBackground, in: .rect(cornerRadius: 8))
            .environment(\.layoutDirection, .leftToRight)
        case .table(let header, let rows, let align):
            MdTable(header: header, rows: rows, align: align, context: context)
        case .image(let url, let alt):
            if let resolved = context.imageURL(url) {
                MdImage(url: resolved, alt: alt)
            } else if !alt.isEmpty {
                Text(verbatim: alt)
            }
        case .rule:
            Divider()
        }
    }
}

/// Each column is as wide as its widest cell; cells don't wrap (the table scrolls).
private struct MdTable: View {
    let header: [[MdInline]]
    let rows: [[[MdInline]]]
    let align: [Int]
    let context: MdContext

    var body: some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        cell(c < header.count ? header[c] : [], column: c, isHeader: true)
                    }
                }
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            cell(c < rows[r].count ? rows[r][c] : [], column: c, isHeader: false)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator))
            }
            .padding(0.5)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func cell(_ inlines: [MdInline], column: Int, isHeader: Bool) -> some View {
        let a = column < align.count ? align[column] : -1
        return context.text(inlines, weight: isHeader ? .bold : nil)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: a == 0 ? .center : a == 1 ? .trailing : .leading)
            .background(isHeader ? MdMetrics.codeBackground : .clear)
            .overlay {
                Rectangle().strokeBorder(Color(uiColor: .separator), lineWidth: 0.25)
            }
    }
}

/// At its own size, one image pixel per point like Kotlin's (an emote stays small),
/// shrunk to fit the width; tapping opens it. The size is only known after loading:
/// the loaded image stays in `ImageLoader`'s memory cache, so `RemoteImage` paints it
/// in its first frame and a reused cell has its height right away.
private struct MdImage: View {
    let url: URL
    let alt: String

    @State private var loaded: (url: URL, size: CGSize)?
    @State private var failed: URL?
    @Environment(\.openURL) private var openURL

    private var size: CGSize? {
        if let loaded, loaded.url == url { return loaded.size }
        return ImageLoader.shared.cached(url: url, maxPixelSize: MdMetrics.imagePixels, animated: true).map(Self.pixels)
    }

    private static func pixels(_ image: UIImage) -> CGSize {
        let first = image.images?.first ?? image
        return CGSize(width: first.size.width * first.scale, height: first.size.height * first.scale)
    }

    var body: some View {
        Group {
            if let size, size.width > 0, size.height > 0 {
                Button {
                    if let target = MdAction.link(url.absoluteString).url { openURL(target) }
                } label: {
                    RemoteImage(url: url, contentMode: .fit, animated: true, maxPixelSize: MdMetrics.imagePixels)
                        .aspectRatio(size.width / size.height, contentMode: .fit)
                        .frame(maxWidth: size.width, maxHeight: 400)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(alt)
            } else if failed == url {
                if !alt.isEmpty { Text(verbatim: alt) }
            } else {
                Color(uiColor: .secondarySystemFill)
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 12))
                    .task(id: url) {
                        let url = url
                        guard let image = await ImageLoader.shared.image(url: url, maxPixelSize: MdMetrics.imagePixels, animated: true) else {
                            if !Task.isCancelled { failed = url }
                            return
                        }
                        loaded = (url, Self.pixels(image))
                    }
            }
        }
    }
}
