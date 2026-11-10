import SwiftUI

/// Depth-guide colours (rotate by nesting level).
let railColors: [UIColor] = [0xFF9F8BE8, 0xFF62B5AA, 0xFFE0A55C, 0xFFD88FB4, 0xFF7E9BE0].map { UIColor(Color(argb: $0)) }

/// One row of the list as a plain value, without its replies, so comparing two is
/// cheap and a change to any one row reconfigures that row alone.
struct CommentRowModel: Equatable {
    var comment: Comment
    var collapsed = false
    /// Comments under this one when they're folded away ("Show N replies"), else nil.
    var foldedReplies: Int? = nil
    var isNew = false
    var isOwn = false
    var isOp = false
    var highlighted = false
    /// A "more" row being fetched.
    var loading = false
    /// Where it sits in its top-level thread's container (Calm).
    var first = false
    var last = false
}

/// What every row reads from settings and the screen. A change reconfigures all rows on screen.
struct ThreadRowEnv: Equatable {
    var calm = true
    var tapToCollapse = false
    var voteEdge = true
    var voteGlow = true
    var dark = false
    var textScale = 1.0
    var accent = Color.accentColor

    /// The flat list's (and the guides') indentation.
    func indent(_ depth: Int) -> CGFloat {
        calm ? 12 + CGFloat(min(max(depth, 0), 8)) * 10 : 10 + CGFloat(min(max(depth, 0), 6)) * 8
    }
}

/// `UIHostingConfiguration` doesn't inherit the SwiftUI environment across UIKit:
/// what `ilayTheme` sets at the root has to be set again on every cell.
private struct CellTheme: ViewModifier {
    let env: ThreadRowEnv

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(IlayTheme.typeSize(env.textScale).map { $0...$0 } ?? (.xSmall ... .accessibility5))
            .tint(env.accent)
            .environment(\.voteColors, IlayTheme.voteColors(dark: env.dark))
    }
}

extension View {
    func threadCellTheme(_ env: ThreadRowEnv) -> some View { modifier(CellTheme(env: env)) }
}

/// A post's or comment's text, cut into markdown and media.
enum CommentBody {
    /// Link-heavy comments can't blow up the list.
    static let maxMedia = 3
    static let maxPostMedia = 10

    private final class Box {
        let segments: [BodySegment]
        init(_ s: [BodySegment]) { segments = s }
    }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 6000
        return c
    }()

    /// Worked out once per body (off the main actor, by the view model's prewarm): a rebind just reads it.
    static func segments(_ c: Comment) -> [BodySegment] {
        if let hit = cache.object(forKey: c.body as NSString) { return hit.segments }
        let s = bodySegments(c.body, c.media, maxMedia)
        cache.setObject(Box(s), forKey: c.body as NSString)
        return s
    }
}

/// A flat thread row, like Apollo's or a Mail thread: name and age, the text, then a
/// quiet row of plain symbols. Nothing here reads shared observable state: a row
/// redraws only when its value changes.
struct CommentRowView: View {
    let row: CommentRowModel
    let env: ThreadRowEnv
    let actions: ThreadActions
    /// Where the name line ends, in the row: a long press above it collapses rather than
    /// opening the menu (`CommentListController`'s context menu).
    var onHeaderBottom: (CGFloat) -> Void = { _ in }

    private var c: Comment { row.comment }

    var body: some View {
        Group {
            if env.calm {
                content
                    .padding(.leading, env.indent(c.depth))
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                    .padding(.bottom, row.collapsed ? 8 : 2)
                    .padding(.top, row.first ? 5 : 0)
                    .padding(.bottom, row.last ? 15 : 0)
                    .padding(.horizontal, 12)
            } else {
                card
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(.named(CommentRowView.space))
        .threadCellTheme(env)
    }

    private static let space = "commentRow"

    /// The cards setting: each comment on its own rounded card, its depth colour on the edge.
    private var card: some View {
        content
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, row.collapsed ? 10 : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                if c.depth > 0 {
                    Color(uiColor: railColors[(c.depth - 1) % railColors.count]).frame(width: 3)
                }
            }
            .background(row.highlighted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .clipShape(.rect(cornerRadius: 14))
            .padding(.leading, env.indent(c.depth))
            .padding(.trailing, 10)
            .padding(.bottom, 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if row.collapsed {
                Text(verbatim: c.body.replacingOccurrences(of: "\n", with: " "))
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                body(of: c)
                    .contentShape(.rect)
                    .gesture(env.tapToCollapse ? TapGesture().onEnded { actions.toggle(c) } : nil)
                CommentActionsRow(row: row, calm: env.calm, actions: actions)
                if let n = row.foldedReplies {
                    Button {
                        actions.unfold(c)
                    } label: {
                        Label(n == 1 ? "Show 1 reply" : "Show \(n) replies", systemImage: "chevron.down")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    /// Long-press collapses the whole subtree; tap re-expands a collapsed comment
    /// (so a tap can't accidentally collapse) unless tap-to-collapse is on. A long
    /// press anywhere else on the comment opens its menu.
    private var header: some View {
        HStack(spacing: 6) {
            // Tapping the name opens the commenter's profile.
            HStack(spacing: 8) {
                if env.calm { AuthorDot(name: c.author) }
                Text(verbatim: c.author)
                    .font(.footnote.weight(env.calm ? .medium : .semibold))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            .onTapGesture {
                if c.author != "[deleted]" { app.navigator.openUser(c.author) }
            }
            if row.isOp { Tag("OP", tint: env.accent) }
            if c.stickied { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.green).accessibilityLabel("Pinned") }
            if let flair = c.authorFlair { FlairChip(flair: flair) }
            Text(verbatim: "· \(timeAgo(c.createdUtc))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            if row.isNew { Tag("NEW", tint: .orange) }
            Spacer(minLength: 0)
            if row.collapsed {
                if env.calm {
                    GlassPill(symbol: "arrow.up.and.line.horizontal.and.arrow.down", label: "Expand", haptic: true) { actions.toggle(c) }
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Expand")
                }
            }
        }
        .frame(minHeight: 24)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(CommentRowView.space)).maxY } action: { onHeaderBottom($0) }
        .contentShape(.rect)
        .onTapGesture {
            if row.collapsed || env.tapToCollapse { actions.toggle(c) }
        }
        .onLongPressGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            actions.toggle(c)
        }
    }

    private var nameColor: Color {
        if c.distinguished == "moderator" { return .green }
        return row.isOwn ? env.accent : .primary
    }

    private func body(of c: Comment) -> some View {
        // Plain text, not selectable: a selectable paragraph is far heavier to
        // build while scrolling through hundreds of comments (and swallows
        // taps for tap-to-collapse). "Select text" is in the menu.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(CommentBody.segments(c).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown): RedditMarkdown(text: markdown, media: c.media)
                case .media(let uri): CommentMediaView(uri: uri)
                }
            }
        }
    }
}

/// ↑ score ↓ · Reply · (saved) · Collapse · ⋯
private struct CommentActionsRow: View {
    let row: CommentRowModel
    let calm: Bool
    let actions: ThreadActions
    @Environment(\.voteColors) private var votes

    private var c: Comment { row.comment }

    var body: some View {
        let up = c.likes == true
        let down = c.likes == false
        if calm {
            // Glass pills, the same design as the post's buttons (drawn: see GlassPillStyle).
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    GlassPill(symbol: "arrow.up", value: c.scoreHidden ? "–" : compactNumber(c.score),
                              valueTint: down ? votes.down : nil, label: "Upvote", on: up, tint: votes.up,
                              leading: 16, trailing: 5, haptic: true, bounces: false) { actions.vote(c, 1) }
                    GlassPill(symbol: "arrow.down", label: "Downvote", on: down, tint: votes.down,
                              leading: 5, trailing: 16, haptic: true, bounces: false) { actions.vote(c, -1) }
                }
                // Deep rows have no width for the word: it broke into "Re-ply".
                GlassPill(symbol: "arrowshape.turn.up.left", value: c.depth < 3 ? "Reply" : nil, label: "Reply") { actions.reply(c) }
                Spacer(minLength: 0)
                if c.saved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Saved")
                        .padding(.trailing, 2)
                }
                GlassPill(symbol: "arrow.down.and.line.horizontal.and.arrow.up", label: "Collapse thread", haptic: true) { actions.toggle(c) }
                CommentMenuButton { actions.menu(c, isOwn: row.isOwn) }
                    .frame(width: 32, height: 32)
            }
            // Like Apple's bar controls: past this the row no longer fits a phone's width.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.top, 4)
        } else {
            HStack(spacing: 0) {
                VoteArrow(symbol: "arrow.up", label: "Upvote", on: up, tint: votes.up) { actions.vote(c, 1) }
                Text(verbatim: c.scoreHidden ? "–" : compactNumber(c.score))
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(up ? votes.up : down ? votes.down : .secondary)
                VoteArrow(symbol: "arrow.down", label: "Downvote", on: down, tint: votes.down) { actions.vote(c, -1) }
                Button {
                    actions.reply(c)
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .labelStyle(.iconOnly)
                        .font(.footnote)
                        .frame(width: 44, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if c.saved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Saved")
                        .padding(.trailing, 8)
                }
                Button {
                    actions.toggle(c)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.footnote)
                        .frame(width: 38, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Collapse thread")
                CommentMenuButton { actions.menu(c, isOwn: row.isOwn) }
                    .frame(width: 38, height: 34)
            }
            .padding(.leading, -12)
        }
    }
}

/// A Calm button (comments, and the feed's cards): a glass pill like the post's (outer
/// corners round, inner ones tighter where two join). A vote tints it with its colour;
/// the symbol pops on your tap only, never when a reused cell changes post or comment.
struct GlassPill: View {
    let symbol: String
    var value: String? = nil
    var valueTint: Color? = nil
    let label: String
    var on = false
    var tint: Color = .primary
    var leading: CGFloat = 16
    var trailing: CGFloat = 16
    var height: CGFloat = 32
    var font: Font = .footnote.weight(.medium)
    /// A light tap felt on press: for votes, save and collapse, not for buttons that open something.
    var haptic = false
    /// Votes don't pop (#141).
    var bounces = true
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                           bottomTrailingRadius: trailing, topTrailingRadius: trailing)
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).symbolEffect(.bounce, value: bounces ? taps : 0)
                if let value {
                    Text(verbatim: value).monospacedDigit().lineLimit(1).fixedSize()
                        .foregroundStyle(valueTint ?? (on ? tint : .primary))
                }
            }
            .font(font)
            .foregroundStyle(on ? tint : .primary)
            .padding(.horizontal, 11)
            .frame(minWidth: 40, minHeight: height)
            .contentShape(shape)
        }
        .buttonStyle(GlassPillStyle(shape: shape, on: on, tint: tint))
        .sensoryFeedback(trigger: taps) { _, _ in haptic ? .impact(weight: .light) : nil }
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The glass pill drawn rather than live: `.glassEffect(.regular.interactive())` on four
/// pills a comment (and five a feed card) made scrolling costly. On the flat cards the
/// system glass is a plain platter, so this paints what it showed there (measured off
/// screenshots): white with a soft shadow in light, a darker platter with a hairline rim in
/// dark, the vote's colour at 35% over it, and a grow under the finger like interactive glass.
private struct GlassPillStyle: ButtonStyle {
    let shape: UnevenRoundedRectangle
    let on: Bool
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        configuration.label
            .background {
                shape.fill(dark ? Color.black.opacity(0.24) : .white)
                    .shadow(color: .black.opacity(dark ? 0 : 0.1), radius: 14, y: 4)
                    .overlay { if on { shape.fill(tint.opacity(0.35)) } }
                    .overlay {
                        shape.strokeBorder(on ? (dark ? tint.opacity(0.7) : .white.opacity(0.6)) : .white.opacity(dark ? 0.14 : 0.9), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 1.06 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A commenter's initial on a colour picked from their name, so one person keeps
/// their colour down a thread; their profile picture over it once it's known (#133).
private struct AuthorDot: View {
    let name: String

    var body: some View {
        let deleted = name.isEmpty || name.hasPrefix("[")
        let icon = deleted || !app.settings.value.commentAvatars ? nil : app.authorAvatars.icons[name.lowercased()]
        Text(verbatim: deleted ? "?" : String(name.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(deleted ? Color(.systemGray) : avatarColor(name), in: .circle)
            .overlay {
                if let icon {
                    RemoteImage(url: URL(string: icon)) { Color.clear }
                        .clipShape(.circle)
                }
            }
    }
}

/// One vote symbol: coloured when on, with no pop (#141).
private struct VoteArrow: View {
    let symbol: String
    let label: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(on ? tint : .secondary)
                .frame(width: 36, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// ⋯: a UIKit button whose menu is only built when it opens, so a row costs nothing
/// for it. The same menu as the long press.
private struct CommentMenuButton: UIViewRepresentable {
    let items: () -> [UIMenuElement]

    final class Coordinator {
        var items: () -> [UIMenuElement] = { [] }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote))
        config.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "More"
        button.showsMenuAsPrimaryAction = true
        let coordinator = context.coordinator
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { done in done(coordinator.items()) }])
        return button
    }

    func updateUIView(_ view: UIButton, context: Context) {
        context.coordinator.items = items
    }
}

/// A small label beside a name.
private struct Tag: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 4))
            .fixedSize()
    }
}

/// A user's flair in this community, next to their name (#31): its text, with its emoji drawn inline.
struct FlairChip: View {
    let flair: UserFlair

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(flair.parts.enumerated()), id: \.offset) { _, part in
                if let url = part.emojiUrl.flatMap(URL.init(string:)) {
                    RemoteImage(url: url, contentMode: .fit, maxPixelSize: 48) { Color.clear }
                        .frame(width: 13, height: 13)
                } else if let text = part.text {
                    Text(verbatim: text).lineLimit(1)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(.tint.opacity(0.16), in: .rect(cornerRadius: 4)) // tinted, as post flairs (#131)
        .frame(maxWidth: 140, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An image, GIF or video linked in a comment. The slot's size is known before the
/// image is, so a row keeps its height as images load: a row growing under the finger
/// is what makes a thread feel jumpy.
struct CommentMediaView: View {
    let uri: URL

    var body: some View {
        Button {
            app.navigator.openLink(uri.absoluteString)
        } label: {
            if isVideoUrl(uri) {
                Color(.tertiarySystemFill)
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Play")
            } else {
                image
                    .overlay(alignment: .topTrailing) {
                        if isGifUrl(uri) {
                            Text(verbatim: "GIF")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.54), in: .rect(cornerRadius: 6))
                                .padding(6)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .clipShape(.rect(cornerRadius: 12))
        .zoomSource()
    }

    /// Reddit's preview links carry their size; other images get a fixed slot.
    private var image: some View {
        let query = URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let w = query.first { $0.name == "width" }?.value.flatMap(Double.init)
        let h = query.first { $0.name == "height" }?.value.flatMap(Double.init)
        let view = RemoteImage(url: uri, contentMode: .fit, animated: true) { Color(.tertiarySystemFill) }
        return Group {
            if let w, let h, h > 0 {
                view.aspectRatio(min(max(w / h, 0.5), 2), contentMode: .fit).frame(maxHeight: 260, alignment: .leading)
            } else {
                view.frame(height: 220).background(Color(.quaternarySystemFill))
            }
        }
    }
}

/// "Load more replies" node: a light indented row. A stub with no ids is "continue this thread".
struct MoreRowView: View {
    let row: CommentRowModel
    let env: ThreadRowEnv
    let actions: ThreadActions

    var body: some View {
        let c = row.comment
        Button {
            actions.loadMore(c)
        } label: {
            HStack(spacing: 8) {
                if row.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: c.moreChildren.isEmpty ? "arrow.turn.down.right" : "plus.circle")
                }
                Text(c.moreChildren.isEmpty ? "Continue thread" : "\(c.moreCount) more replies")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.vertical, 12)
            .padding(.leading, env.indent(c.depth))
            .padding(.trailing, env.calm ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(row.loading)
        .padding(.top, env.calm && row.first ? 5 : 0)
        .padding(.bottom, env.calm && row.last ? 15 : 0)
        .padding(.horizontal, env.calm ? 12 : 0)
        .threadCellTheme(env)
    }
}
