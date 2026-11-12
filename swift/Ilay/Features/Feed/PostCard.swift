import SwiftUI

/// A post in a feed, in the layout chosen in Settings (Default / Cards / Mini cards /
/// Calm / Calm cards). Everything it shows was worked out when the post loaded (see
/// `PostRow`), so its body stays shallow: live state (votes, read) is read only by the
/// small views that show it, so only those re-run when it changes.
struct PostCard: View {
    let row: PostRow

    /// For a post outside `PostListView`, e.g. in a `PagedList` row.
    @MainActor init(post: Post, width: CGFloat? = nil) {
        // A crosspost rebuilt around its original once that has loaded.
        row = PostRow(app.repository.crossposts.merged(post), config: .current(width: width))
    }

    init(row: PostRow) { self.row = row }

    var body: some View {
        let actions = PostActions(post: row.post)
        // The whole card, "why" banner included, is one target: inner buttons win over this tap.
        VStack(alignment: .leading, spacing: 0) {
            // "Why you're seeing this" banner (For You feed only). Calm shows the
            // reason in the card header instead.
            if let reason = row.post.feedReason, !row.config.display.isCalm {
                ReasonRow(reason: reason, a: actions, inset: row.config.cardInset + row.config.contentInset)
            }
            switch row.config.display {
            case .large: LargeCard(row: row, a: actions)
            case .card: CardsCard(row: row, a: actions)
            case .mini: MiniCard(row: row, a: actions)
            case .calm: CalmCard(row: row, a: actions)
            case .calmCards: CalmCardsCard(row: row, a: actions)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.openDetail)
    }
}

// MARK: - Layouts

private struct LargeCard: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(row: row, a: a)
            CardTitle(row: row, font: .headline).padding(.top, 8)
            TextBelowTitle(row: row)
            CardMedia(row: row, a: a, radius: 12).padding(.top, row.kind == .text ? 0 : 10)
            PollOptionsView(post: row.post).padding(.top, row.post.pollOptions.isEmpty ? 0 : 8)
            CardSnippet(row: row, lines: 3)
            ActionsRow(row: row, a: a).padding(.top, 4)
        }
        .padding(.leading, row.config.contentInset)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .overlay { ReadVeil(row: row) }
    }
}

/// "Cards" — a full-width card like the default, but with media capped to a shorter
/// banner height so cards stay compact and scannable.
private struct CardsCard: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(row: row, a: a)
            CardTitle(row: row, font: .headline).padding(.top, 8)
            TextBelowTitle(row: row)
            CardMedia(row: row, a: a, radius: 12).padding(.top, row.kind == .text ? 0 : 10)
            PollOptionsView(post: row.post).padding(.top, row.post.pollOptions.isEmpty ? 0 : 8)
            CardSnippet(row: row, lines: 2)
            ActionsRow(row: row, a: a).padding(.top, 4)
        }
        .padding(.leading, row.config.contentInset)
        .padding(.trailing, 6)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .modifier(CardSurface(row: row))
    }
}

/// "Mini cards" — compact: header + title with a small side thumbnail, full action row below.
private struct MiniCard: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(row: row, a: a)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle(row: row, font: .subheadline.weight(.semibold), lines: 3)
                    TextBelowTitle(row: row)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if case let .thumbnail(url, pixels, symbol, play) = row.media {
                    // The thumbnail opens the media full screen, as tapping media does on the
                    // other layouts (a link opens the link); the rest of the card opens the
                    // post (#104). Blurred (NSFW/spoiler) ones keep opening the post, so a
                    // tap never shows them uncovered.
                    if row.blur {
                        Thumbnail(url: url, pixels: pixels, symbol: symbol, play: play)
                    } else {
                        Button(action: a.openMedia) {
                            Thumbnail(url: url, pixels: pixels, symbol: symbol, play: play).zoomSource()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open media")
                    }
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            ActionsRow(row: row, a: a).padding(.top, 2)
        }
        .padding(.leading, row.config.contentInset)
        .padding(.trailing, 6)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .overlay { ReadVeil(row: row) }
    }
}

/// "Calm" — one card per post: a rounded-square avatar header, a bold title, a flair,
/// media at its full aspect ratio and the vote + comment symbols. Mark-read lives in the
/// ⋮ sheet and the long-press menu.
private struct CalmCard: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CalmBody(row: row, a: a, media: true)
                .padding(.trailing, 3)
            CalmActions(row: row, a: a)
                .padding(.top, 8)
                .padding(.bottom, 6)
                // With the card's 5, as far from the right edge as the votes are from the left.
                .padding(.trailing, 6)
        }
        .padding(.leading, row.config.contentInset)
        .padding(.trailing, 5)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .modifier(CardSurface(row: row))
    }
}

/// "Calm cards" — each post its own connected group: the content, the media (edge to
/// edge) and the actions as separate segments, 3pt apart.
private struct CalmCardsCard: View {
    let row: PostRow
    let a: PostActions

    private let outer: CGFloat = 20
    private let inner: CGFloat = 6

    var body: some View {
        VStack(spacing: 3) {
            CalmBody(row: row, a: a, media: false)
                .padding(.leading, row.config.contentInset)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(topLeadingRadius: outer, bottomLeadingRadius: inner, bottomTrailingRadius: inner, topTrailingRadius: outer))
            if row.kind != .text {
                CardMedia(row: row, a: a, radius: inner)
            }
            CalmActions(row: row, a: a)
                .padding(6)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(topLeadingRadius: inner, bottomLeadingRadius: outer, bottomTrailingRadius: outer, topTrailingRadius: inner))
        }
        .overlay { ReadVeil(row: row) }
        .padding(.horizontal, row.config.cardInset)
        .padding(.bottom, 12)
    }
}

/// A Cards or Calm card's rounded page-coloured surface. No glass here: it's content.
private struct CardSurface: ViewModifier {
    let row: PostRow

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .overlay { ReadVeil(row: row, radius: 20) }
            .padding(.horizontal, row.config.cardInset)
            .padding(.bottom, 12)
    }
}

// MARK: - Read state

/// Dims an already-viewed post when history tracking is on (Settings → Dim read posts; not when it's Off, #106).
/// A page-colour veil looks the same as 55% opacity without re-rendering the whole card,
/// images and all, into an offscreen layer every frame it scrolls. Reads the history
/// itself, so marking a post read costs this view rather than the card.
private struct ReadVeil: View {
    let row: PostRow
    var radius: CGFloat = 0

    var body: some View {
        if row.config.trackHistory, row.config.dimRead, !row.config.dimReadTextOnly, app.history.contains(row.id) {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(row.config.isCarded ? .systemGroupedBackground : .systemBackground).opacity(0.45))
                .allowsHitTesting(false)
        }
    }
}

/// Fades a read post's title / text when only text is dimmed (images stay bright).
private struct ReadDimmed<Content: View>: View {
    let row: PostRow
    @ViewBuilder let content: Content

    var body: some View {
        if row.config.trackHistory, row.config.dimRead, row.config.dimReadTextOnly {
            content.opacity(app.history.contains(row.id) ? 0.5 : 1)
        } else {
            content
        }
    }
}

// MARK: - Parts

/// Long-press anywhere on the card tunes For You via its menu; this is the discoverable
/// entry to the feed-tuning sheet, so "show less from this subreddit" isn't hidden.
private struct ReasonRow: View {
    let reason: String
    let a: PostActions
    let inset: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(reason).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: a.tune) {
                Label("Tune", systemImage: "slider.horizontal.3").padding(.vertical, 2).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
        .padding(.leading, inset)
        .padding(.trailing, inset)
        .padding(.top, 4)
    }
}

private struct CardHeader: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        HStack(spacing: 8) {
            Button(action: a.openSubreddit) { FeedAvatar(row: row, size: 28, radius: 14) }
                .buttonStyle(.plain)
                .accessibilityLabel(row.subredditLabel)
            // Tapping the "u/author" part of the header opens their profile; the
            // rest opens the subreddit.
            HStack(spacing: 4) {
                Button(action: a.openSubreddit) {
                    Text(row.subredditLabel).fontWeight(.semibold).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                Text("·")
                Button(action: a.openAuthor) { Text(row.authorLabel) }.buttonStyle(.plain)
                Text("·")
                Text(row.timeLabel).layoutPriority(1)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 0)
            HeaderBadges(post: row.post)
        }
        .padding(.trailing, 8)
    }
}

private struct CalmHeader: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        HStack(spacing: 10) {
            Button(action: a.openSubreddit) { FeedAvatar(row: row, size: 36, radius: 18) } // a circle (#169)
                .buttonStyle(.plain)
                .accessibilityLabel(row.subredditLabel)
            VStack(alignment: .leading, spacing: 1) {
                Button(action: a.openSubreddit) {
                    Text(row.subredditLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                }
                .buttonStyle(.plain)
                if let reason = row.calmReason {
                    // For You: why it's here, in place of the author, then the post's
                    // age (kept visible when the reason is long). Tap → the "why you're
                    // seeing this" / tune sheet.
                    Button(action: a.tune) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").foregroundStyle(.tint)
                            Text(reason).fontWeight(.medium).foregroundStyle(.tint).lineLimit(1)
                            Text("· \(row.timeLabel)").foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: a.openAuthor) {
                        Text("\(row.authorLabel) · \(row.timeLabel)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            HeaderBadges(post: row.post)
            Button(action: a.more) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
    }
}

private struct HeaderBadges: View {
    let post: Post

    var body: some View {
        if post.stickied {
            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint).accessibilityLabel("Pinned")
        }
        if post.over18 {
            Text("NSFW")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.14), in: .rect(cornerRadius: 5))
        }
    }
}

/// The subreddit's icon, or its first letter on a tone of its own.
private struct FeedAvatar: View {
    let row: PostRow
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(tone).opacity(row.config.display.isCalm ? 0.16 : 1)
            if let url = row.avatarUrl {
                // Always a still image: some subreddit icons are animated GIFs (see RemoteImage).
                SlotImage(url: url, pixels: row.avatarPixels).frame(width: size, height: size)
            } else {
                // Soft tones like every placeholder (#168).
                let tones = avatarTones(row.post.subreddit)
                tones.background
                Text(row.post.subreddit.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(tones.letter)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: radius))
    }

    private var tone: AnyShapeStyle {
        guard row.config.display.isCalm else { return AnyShapeStyle(Color(.secondarySystemFill)) }
        switch row.tone {
        case 0: return AnyShapeStyle(.tint)
        case 1: return AnyShapeStyle(.indigo)
        default: return AnyShapeStyle(.teal)
        }
    }
}

private struct CardTitle: View {
    let row: PostRow
    let font: Font
    var lines: Int? = nil

    var body: some View {
        ReadDimmed(row: row) {
            Text(row.post.title)
                .font(font)
                .foregroundStyle(.primary)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What sits under the title in every layout: flair and crosspost line.
private struct TextBelowTitle: View {
    let row: PostRow

    var body: some View {
        if !row.flair.isEmpty {
            FlairView(runs: row.flair, symbol: row.config.display.isCalm ? row.flairSymbol : nil).padding(.top, 6)
        }
        if let from = row.post.crosspostFrom {
            // A tap opens the original post and its comments (#100), not the card's post.
            Button {
                if let id = row.post.crosspostId { app.navigator.push(.post(subreddit: from, postId: id)) }
            } label: {
                Label("Crossposted from \(crosspostSource(from))", systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(row.post.crosspostId == nil)
            .accessibilityHint("Opens the original post")
            .padding(.top, 6)
        }
        ReminderLine(post: row.post)
    }
}

/// "Reminder tomorrow at 09:00" on a post you asked to be reminded about; tap to change or cancel.
struct ReminderLine: View {
    let post: Post

    var body: some View {
        if let due = PostReminders.shared.pending[post.id] {
            Button { PostReminders.manage(post) } label: {
                Label("Reminder \(whenLabel(due))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }
}

private struct CardSnippet: View {
    let row: PostRow
    let lines: Int

    var body: some View {
        if !row.snippet.isEmpty {
            ReadDimmed(row: row) {
                Text(row.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(lines)
                    .multilineTextAlignment(.leading)
            }
            .padding(.top, 6)
            .padding(.trailing, 8)
        }
    }
}

/// A flair's words and images in one line. Public: the post screen shows it too.
struct FlairView: View {
    let runs: [FlairRun]
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.tint) }
            ForEach(runs.indices, id: \.self) { i in
                if let emoji = runs[i].emoji {
                    SlotImage(url: emoji, pixels: 48).frame(width: 14, height: 14)
                } else if let text = runs[i].text {
                    Text(text).lineLimit(1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // A light tint of the accent: white flair emoji and text stay readable (#131).
        .background(.tint.opacity(0.16), in: .capsule)
    }
}

/// Header, title, flair, crosspost, media (when `media`), poll and selftext.
private struct CalmBody: View {
    let row: PostRow
    let a: PostActions
    let media: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CalmHeader(row: row, a: a)
            CardTitle(row: row, font: .headline).padding(.top, 8)
            TextBelowTitle(row: row)
            if media, row.kind != .text {
                CardMedia(row: row, a: a, radius: 16).padding(.top, 10)
            }
            PollOptionsView(post: row.post).padding(.top, row.post.pollOptions.isEmpty ? 0 : 10)
            CardSnippet(row: row, lines: 2)
        }
    }
}

// MARK: - Media

private struct CardMedia: View {
    let row: PostRow
    let a: PostActions
    let radius: CGFloat

    var body: some View {
        switch row.media {
        case .none, .thumbnail:
            EmptyView()
        case let .image(url, height, pixels, play, pill):
            // No `.id(row.id)`: it rebuilt the image view on every cell reuse. NsfwBlur
            // keys its reveal by `id` instead.
            NsfwBlur(blur: row.blur, blurredImageUrl: row.post.blurredPreviewUrl, label: row.blurLabel, id: row.id, radius: radius) {
                Button(action: a.openMedia) {
                    SlotImage(url: url, pixels: pixels, brokenSymbol: "photo.badge.exclamationmark")
                        .frame(height: height)
                        .frame(maxWidth: .infinity)
                        .overlay { if play { PlayBadge() } }
                        .overlay(alignment: pill?.leading == true ? .topLeading : .topTrailing) {
                            if let pill { MediaPill(info: pill).padding(8) }
                        }
                        .clipShape(.rect(cornerRadius: radius))
                        .zoomSource()
                }
                .buttonStyle(.plain)
            }
        case let .video(url, poster, height):
            InlineVideo(url: url, height: height, poster: poster, onTap: a.openMedia)
                .clipShape(.rect(cornerRadius: radius))
                .zoomSource()
        case let .gallery(carouselHeight, height):
            // Its own view per post: a reused cell mustn't keep the last post's page (or
            // reveal). A spoiler / NSFW gallery covers each image, so it still swipes (#165).
            let cover = row.blur ? row.blurLabel : nil
            Group {
                if let carouselHeight {
                    GalleryM3Carousel(images: row.post.gallery, title: row.post.title, height: carouselHeight, cover: cover)
                } else {
                    GalleryCarousel(images: row.post.gallery, title: row.post.title, height: height, radius: radius, cover: cover)
                }
            }
            .id(row.id)
        case let .link(thumb, thumbPixels, hero, heroHeight, heroPixels):
            Button(action: a.openMedia) {
                if row.config.display.isCalm {
                    CalmLink(row: row, hero: hero, height: heroHeight, pixels: heroPixels, radius: radius)
                } else {
                    PlainLink(domain: row.inAppLinkLabel ?? row.post.domain, external: row.inAppLinkLabel == nil, thumb: thumb, pixels: thumbPixels)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PlainLink: View {
    let domain: String
    let external: Bool
    let thumb: URL?
    let pixels: Int

    var body: some View {
        HStack(spacing: 12) {
            if let thumb {
                SlotImage(url: thumb, pixels: pixels).frame(width: 72, height: 72)
            } else {
                Image(systemName: "link").foregroundStyle(.secondary).frame(width: 72, height: 72)
            }
            Text(domain).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            if external { Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.tertiary).padding(.trailing, 12) }
        }
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct CalmLink: View {
    let row: PostRow
    let hero: URL?
    let height: CGFloat
    let pixels: Int
    let radius: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if let hero {
                // The card clips it: a square cover, so its corners don't show inside (#165).
                NsfwBlur(blur: row.blur, blurredImageUrl: row.post.blurredPreviewUrl, label: row.blurLabel, id: row.id, radius: 0) {
                    SlotImage(url: hero, pixels: pixels).frame(height: height).frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "link")
                Text(row.inAppLinkLabel ?? row.post.domain).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if row.inAppLinkLabel == nil { Image(systemName: "arrow.up.right") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: radius))
        .clipShape(.rect(cornerRadius: radius))
    }
}

/// Small square thumbnail for the mini layout.
private struct Thumbnail: View {
    let url: URL?
    let pixels: Int
    let symbol: String
    let play: Bool

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if url != nil {
                SlotImage(url: url, pixels: pixels, brokenSymbol: "link")
            } else {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            if play {
                Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(.white)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct PlayBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 26))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.black.opacity(0.5), in: Circle())
            .accessibilityLabel("Play")
    }
}

private struct MediaPill: View {
    let info: MediaPillInfo

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = info.symbol { Image(systemName: symbol) }
            Text(info.label)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.54), in: .capsule)
    }
}

// MARK: - Actions

/// ↑ score ↓ as plain symbols, tinted once voted. Reads the shared overrides itself (kept
/// in sync with the post screen), so a vote re-runs this and not the card.
struct VoteCluster: View {
    let post: Post
    let a: PostActions

    @Environment(\.colorScheme) private var scheme

    init(post: Post, a: PostActions) {
        self.post = post
        self.a = a
    }

    var body: some View {
        let o = app.postOverrides.effective(post)
        let votes = IlayTheme.voteColors(dark: scheme == .dark)
        let up = o.likes == true
        let down = o.likes == false
        HStack(spacing: 0) {
            SymbolButton(on: up, onSymbol: "arrowshape.up.fill", offSymbol: "arrowshape.up", onColor: votes.up, label: "Upvote", bounces: false) { a.vote(1) }
            Text(compactNumber(o.score))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(up ? votes.up : down ? votes.down : .secondary)
                .lineLimit(1)
                .fixedSize()
            SymbolButton(on: down, onSymbol: "arrowshape.down.fill", offSymbol: "arrowshape.down", onColor: votes.down, label: "Downvote", bounces: false) { a.vote(-1) }
        }
    }
}

/// A borderless symbol, 40pt wide to tap, with a bounce when tapped on. The bounce follows a
/// tap count rather than the state: a reused cell going from one post to another mustn't bounce.
private struct SymbolButton: View {
    let on: Bool
    let onSymbol: String
    let offSymbol: String
    /// Nil: the accent.
    var onColor: Color? = nil
    let label: String
    /// Votes don't pop (#141).
    var bounces = true
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: on ? onSymbol : offSymbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(on ? onColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: bounces ? taps : 0)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct CommentsButton: View {
    let post: Post
    let a: PostActions

    var body: some View {
        Button(action: a.openDetail) {
            HStack(spacing: 5) {
                Image(systemName: "bubble.right")
                Text(compactNumber(app.postOverrides.effective(post).numComments)).monospacedDigit().lineLimit(1).fixedSize()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(height: 36)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Comments")
    }
}

private struct ActionsRow: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        HStack(spacing: 0) {
            VoteCluster(post: row.post, a: a).padding(.leading, -10)
            CommentsButton(post: row.post, a: a)
            Spacer(minLength: 0)
            ReadToggle(post: row.post, a: a)
            SaveButton(post: row.post, a: a)
            Button(action: a.more) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
    }
}

/// "Read" toggle shown on every post card (left of Save). Marks the post as read/unread
/// in local history; read posts get a filled, accent check.
private struct ReadToggle: View {
    let post: Post
    let a: PostActions

    var body: some View {
        let seen = app.history.contains(post.id)
        SymbolButton(on: seen, onSymbol: "checkmark.circle.fill", offSymbol: "checkmark.circle", label: seen ? "Mark as unread" : "Mark as read") {
            a.toggleRead(seen: seen)
        }
    }
}

private struct SaveButton: View {
    let post: Post
    let a: PostActions

    var body: some View {
        let saved = app.postOverrides.effective(post).saved
        SymbolButton(on: saved, onSymbol: "bookmark.fill", offSymbol: "bookmark", label: saved ? "Unsave" : "Save") {
            a.toggleSave()
        }
    }
}

/// Calm's actions, the same glass pills as inside the post: ↑ score ↓ joined, comments,
/// then share as media (when it can), share and save. The pills that show a vote, count or
/// save read the shared overrides themselves (as `VoteCluster` does): a vote or save
/// anywhere re-runs those small views, not every card's whole row.
private struct CalmActions: View {
    let row: PostRow
    let a: PostActions

    var body: some View {
        let font = Font.subheadline.weight(.medium)
        HStack(spacing: 8) {
            CalmVotePills(post: row.post, a: a, font: font)
            CalmCommentsPill(post: row.post, a: a, font: font)
            Spacer(minLength: 0)
            if row.canShareMedia {
                GlassPill(symbol: row.post.type == .video || row.post.type == .gif ? "film" : "photo", label: "Share as media",
                          leading: 18, trailing: 18, height: 36, font: font, action: a.shareMedia)
            }
            GlassPill(symbol: "square.and.arrow.up", label: "Share", leading: 18, trailing: 18, height: 36, font: font, action: a.share)
            CalmSavePill(post: row.post, a: a, font: font)
        }
        // Like Apple's bar controls: past this the row no longer fits a phone's width.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct CalmVotePills: View {
    let post: Post
    let a: PostActions
    let font: Font

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let o = app.postOverrides.effective(post)
        let votes = IlayTheme.voteColors(dark: scheme == .dark)
        let up = o.likes == true, down = o.likes == false
        HStack(spacing: 3) {
            GlassPill(symbol: "arrow.up", value: compactNumber(o.score), valueTint: down ? votes.down : nil,
                      label: "Upvote", on: up, tint: votes.up, leading: 18, trailing: 5, height: 36, font: font, haptic: true, bounces: false) { a.vote(1) }
            GlassPill(symbol: "arrow.down", label: "Downvote", on: down, tint: votes.down,
                      leading: 5, trailing: 18, height: 36, font: font, haptic: true, bounces: false) { a.vote(-1) }
        }
    }
}

private struct CalmCommentsPill: View {
    let post: Post
    let a: PostActions
    let font: Font

    var body: some View {
        GlassPill(symbol: "bubble.left", value: compactNumber(app.postOverrides.effective(post).numComments), label: "Comments",
                  leading: 18, trailing: 18, height: 36, font: font, action: a.openDetail)
    }
}

private struct CalmSavePill: View {
    let post: Post
    let a: PostActions
    let font: Font

    var body: some View {
        let saved = app.postOverrides.effective(post).saved
        GlassPill(symbol: saved ? "bookmark.fill" : "bookmark", label: saved ? "Unsave" : "Save", on: saved,
                  tint: IlayTheme.accent, leading: 18, trailing: 18, height: 36, font: font, haptic: true, action: a.toggleSave)
    }
}
