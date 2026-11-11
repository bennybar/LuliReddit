import SwiftUI

/// Translate's state on the post header.
struct PostHeaderTranslate: Equatable {
    var targets: [String] = []
    var shownIn: String? = nil
    var busy = false
    @EquatableIgnored var onPick: (String?) -> Void = { _ in }
}

@propertyWrapper struct EquatableIgnored<Value>: Equatable {
    var wrappedValue: Value
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// What the header keeps across cell reuse: the subreddit's about (its icon and
/// membership), fetched once the thread is in.
@MainActor @Observable final class PostHeaderModel {
    var about: Subreddit?
    var joinedOverride: Bool?
    @ObservationIgnored private var requested = false

    func load(_ subreddit: String) async {
        if requested { return }
        requested = true
        about = try? await app.repository.getSubredditAbout(subreddit)
    }
}

/// The post itself. [fresh]: the post as just fetched with its comments; false for
/// the feed's copy shown while loading, which can be stale.
struct PostHeaderView: View {
    let listed: Post
    /// A crosspost whose original the thread left out fills in once it's fetched.
    private var post: Post { app.repository.crossposts.merged(listed) }
    let fresh: Bool
    let translate: PostHeaderTranslate
    let model: PostHeaderModel

    @Environment(\.voteColors) private var votes
    @Environment(\.layoutDirection) private var direction
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24
    private var nav: AppNavigator { app.navigator }

    var body: some View {
        // The shared state a feed card shows too.
        let o = app.postOverrides.state[post.id]
        let likes = o != nil ? o!.likes : post.likes
        let score = o?.score ?? post.score
        let saved = o?.saved ?? post.saved
        let numComments = o?.numComments ?? post.numComments

        VStack(alignment: .leading, spacing: 0) {
            community
            Text(verbatim: post.title)
                .font(.system(size: titleSize))
                .tracking(-0.24)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            if let flair = post.linkFlair { FlairChip(flair: flair).padding(.top, 8) }
            if let from = post.crosspostFrom {
                // A tap opens the original post and its comments (#100).
                Button {
                    if let id = post.crosspostId { nav.push(.post(subreddit: from, postId: id)) }
                } label: {
                    Label("Crossposted from \(crosspostSource(from))", systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(post.crosspostId == nil)
                .accessibilityHint("Opens the original post")
                .padding(.top, 8)
            }
            ReminderLine(post: post)
            PostMediaView(post: post).padding(.top, 12)
            PollOptionsView(post: post)
            // Gallery/image/link posts can carry a body too: show it whenever
            // there's selftext, not only for pure self-posts.
            PostBodyView(post: post).padding(.top, post.type == .selfPost ? 10 : 0)
            actionRow(score: score, likes: likes, saved: saved, numComments: numComments)
                .padding(.top, 12)
            Text("\(compactNumber(numComments)) comments")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .background { voteGlow(likes) }
        .task(id: fresh) {
            // Icon + membership come from the subreddit's about (fetched once the
            // thread is in; the feed's copy shown while loading skips it).
            if fresh { await model.load(post.subreddit) }
        }
    }

    /// Settings → Mark what you voted on: the comments' glow on the post too (#141), from
    /// its top corner on the end side, fading in from the top so it has no edge under the bar.
    @ViewBuilder private func voteGlow(_ likes: Bool?) -> some View {
        let s = app.settings.value
        if s.voteEdge, s.voteGlow, let likes {
            let c = likes ? votes.up : votes.down
            GeometryReader { g in
                let r = max(min(g.size.height, g.size.width * 0.9), 1)
                RadialGradient(stops: [.init(color: c.opacity(0.34), location: 0), .init(color: c.opacity(0.10), location: 0.45), .init(color: c.opacity(0), location: 1)],
                               center: direction == .rightToLeft ? .topLeading : .topTrailing, startRadius: 0, endRadius: r)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: min(32 / max(g.size.height, 1), 1))],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var community: some View {
        HStack(spacing: 12) {
            Button {
                nav.openSubreddit(post.subreddit)
            } label: {
                LetterAvatar(name: post.subreddit, size: 40, imageUrl: model.about?.iconUrl ?? post.subredditIcon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.subredditPrefixed)
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    nav.openSubreddit(post.subreddit)
                } label: {
                    Text(verbatim: post.subredditPrefixed.nilIfEmpty ?? "r/\(post.subreddit)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Button {
                        nav.openUser(post.author)
                    } label: {
                        Text(verbatim: "u/\(post.author) · \(timeAgo(post.createdUtc))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    if let flair = post.authorFlair { FlairChip(flair: flair) }
                }
            }
            Spacer(minLength: 0)
            joinButton
        }
    }

    @ViewBuilder private var joinButton: some View {
        let joined = model.joinedOverride ?? model.about?.userIsSubscriber
        if !app.session.username.isEmpty, let joined {
            Button(joined ? "Joined" : "Join") {
                let next = !joined
                model.joinedOverride = next
                Task {
                    do {
                        try await app.repository.setSubscribed(post.subreddit, subscribe: next)
                    } catch {
                        model.joinedOverride = !next
                        nav.showActionError(next ? "join" : "leave", error)
                    }
                }
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(joined ? .secondary : .accentColor)
        }
    }

    private func actionRow(score: Int, likes: Bool?, saved: Bool, numComments: Int) -> some View {
        let up = likes == true, down = likes == false
        return HStack(spacing: 0) {
            HStack(spacing: 3) {
                segment("arrow.up", value: compactNumber(score), valueTint: down ? votes.down : nil, label: "Upvote", on: up, tint: votes.up, leading: 20, trailing: 6) { vote(1) }
                segment("arrow.down", label: "Downvote", on: down, tint: votes.down, leading: 6, trailing: 20) { vote(-1) }
            }
            segment("bubble.left", value: compactNumber(numComments), label: "Comments", on: false, tint: .primary, leading: 20, trailing: 20) {}
                .padding(.leading, 8)
            Spacer(minLength: 0)
            if !translate.targets.isEmpty {
                TranslateButton(targets: translate.targets, shownIn: translate.shownIn, busy: translate.busy, onPick: translate.onPick)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            Button {
                app.forYou.forYouLearner.share(post)
                nav.share("https://reddit.com\(post.permalink)", subject: post.title)
            } label: {
                Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40).glassEffect(.regular.interactive(), in: .circle).contentShape(.circle)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .accessibilityLabel("Share")
            Button {
                toggleSave()
            } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .foregroundStyle(saved ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.leading, 6)
            .accessibilityLabel(saved ? "Unsave" : "Save")
        }
        .buttonStyle(.plain)
    }

    /// One piece of a connected button group: 40 tall, outer corners round, inner 6, 3
    /// apart, in glass. A vote tints it with its colour.
    private func segment(
        _ symbol: String, value: String? = nil, valueTint: Color? = nil, label: String, on: Bool, tint: Color,
        leading: CGFloat, trailing: CGFloat, action: @escaping () -> Void
    ) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading, bottomTrailingRadius: trailing, topTrailingRadius: trailing)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol) // no pop on a vote (#141)
                if let value { Text(verbatim: value).monospacedDigit().foregroundStyle(valueTint ?? (on ? tint : .primary)) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(on ? tint : .primary)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .glassEffect(on ? .regular.tint(tint.opacity(0.35)).interactive() : .regular.interactive(), in: shape)
            .contentShape(shape)
        }
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func vote(_ dir: Int) {
        let o = app.postOverrides
        let current = PostOverrides.dirOf(o.effective(post).likes)
        let target = current == dir ? 0 : dir
        o.setVote(post, targetDir: target)
        // Same learning as a vote on the card.
        app.forYou.forYouLearner.vote(post, from: current, to: target)
        Task {
            do {
                try await app.repository.vote(post.fullname, dir: target)
            } catch {
                app.forYou.forYouLearner.vote(post, from: target, to: current)
                o.setVote(post, targetDir: current)
                nav.showActionError("vote", error)
            }
        }
    }

    private func toggleSave() {
        let o = app.postOverrides
        let next = !o.effective(post).saved
        o.setSaved(post, saved: next)
        app.forYou.forYouLearner.save(post, saved: next)
        if next { PostReminders.offer(post) } else { PostReminders.cancel(post.id) }
        Task {
            do {
                try await app.repository.setSaved(post.fullname, saved: next)
            } catch {
                o.setSaved(post, saved: !next)
                app.forYou.forYouLearner.save(post, saved: !next)
                nav.showActionError(next ? "save" : "unsave", error)
            }
        }
    }
}

@MainActor private func openMedia(_ p: Post) {
    let nav = app.navigator
    switch p.type {
    case .image: nav.openImage(p.previewUrl ?? p.url, title: p.title)
    case .gif:
        if let mp4 = p.gifMp4Url {
            nav.openVideo(mp4, title: p.title, downloadUrl: mp4, externalUrl: p.url, gif: true)
        } else {
            nav.openImage(p.url, title: p.title)
        }
    case .gallery: nav.openGallery(p.gallery, title: p.title)
    case .video: nav.openPostVideo(p)
    // A link to a Reddit post (e.g. a crosspost whose original didn't load) opens in Ilay.
    // A share link (`Post.shareLink`) whose original didn't load is resolved on tap.
    case .link:
        if p.shareLink { nav.openLink(p.url) } else if let route = redditPostRoute(p.url) { nav.push(route) } else { nav.openInBrowser(p.url) }
    case .selfPost: break
    }
}

private struct PostMediaView: View {
    let post: Post

    var body: some View {
        let p = post
        let blur = (p.over18 && app.settings.value.blurNsfw) || p.spoiler
        let label = p.over18 ? "NSFW" : "Spoiler"
        if p.type == .selfPost {
            EmptyView()
        } else if p.type == .gallery, !p.gallery.isEmpty {
            NsfwBlur(blur: blur, label: label) {
                if p.gallery.count > 1 {
                    GalleryM3Carousel(images: p.gallery, title: p.title)
                } else {
                    GalleryCarousel(images: p.gallery, title: p.title)
                }
            }
            .padding(.bottom, 12)
        } else if p.type == .link {
            // The link's own picture (a news article's), as its card in the list has it (#130).
            if let preview = p.previewUrl {
                let aspect: CGFloat = {
                    guard let w = p.previewWidth, let h = p.previewHeight, h > 0 else { return 16.0 / 9.0 }
                    return min(max(CGFloat(w) / CGFloat(h), 0.5), 2)
                }()
                NsfwBlur(blur: blur, blurredImageUrl: p.blurredPreviewUrl, label: label) {
                    Button {
                        openMedia(p)
                    } label: {
                        ZStack {
                            Color(.secondarySystemFill)
                            RemoteImage(url: URL(string: preview))
                        }
                        .aspectRatio(aspect, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open link")
                }
                .padding(.bottom, 8)
            }
            Button {
                openMedia(p)
            } label: {
                let inApp = redditLinkLabel(p)
                Label(inApp ?? p.domain, systemImage: inApp == nil ? "arrow.up.right.square" : "link").lineLimit(1)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.bottom, 12)
        } else {
            let url = p.previewUrl ?? (p.type == .image || p.type == .gif ? p.url : nil) ?? p.gallery.first?.url
            let aspect: CGFloat = {
                guard let w = p.previewWidth, let h = p.previewHeight, h > 0 else { return 16.0 / 9.0 }
                return min(max(CGFloat(w) / CGFloat(h), 0.5), 2)
            }()
            NsfwBlur(blur: blur, blurredImageUrl: p.blurredPreviewUrl, label: label) {
                Button {
                    openMedia(p)
                } label: {
                    ZStack {
                        Color(.secondarySystemFill)
                        if let url { RemoteImage(url: URL(string: url), animated: p.type == .gif) }
                        if p.type == .video {
                            Image(systemName: "play.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                                .padding(16)
                                .background(.black.opacity(0.54), in: .circle)
                                .accessibilityLabel("Play")
                        }
                    }
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
                    .zoomSource()
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
    }
}

/// A poll's options, with results once Reddit shows them. Reddit's API can't vote in
/// polls: with the website sign-in, "Vote on Reddit" opens the post signed in (the
/// thread refreshes its results when you come back).
struct PollOptionsView: View {
    let post: Post
    @State private var webSignIn = false

    var body: some View {
        let p = post
        if !p.pollOptions.isEmpty {
            let total = p.pollVotes.reduce(0, +)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(p.pollOptions.enumerated()), id: \.offset) { i, option in
                    let votes = i < p.pollVotes.count ? p.pollVotes[i] : nil
                    let chosen = p.pollChoice == i
                    let share = votes != nil && total > 0 ? Double(votes!) / Double(total) : 0
                    HStack {
                        Text(verbatim: option).fontWeight(chosen ? .bold : nil)
                        Spacer()
                        if votes != nil {
                            Text(verbatim: "\(Int((share * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(alignment: .leading) {
                        if votes != nil {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(chosen ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(Color(.tertiarySystemFill)))
                                    .frame(width: geo.size.width * share)
                            }
                        }
                    }
                    .background(Color(.secondarySystemFill))
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .padding(.bottom, 6)
            Group {
                if p.pollChoice != nil {
                    Text("You voted · \(compactNumber(total)) votes")
                } else if !p.pollVotes.isEmpty {
                    Text("\(compactNumber(total)) votes")
                } else if webSignIn {
                    Button("Vote on Reddit") {
                        app.post.pollVoteOpened = p.id
                        app.navigator.push(.redditWeb(url: "https://www.reddit.com\(p.permalink)", title: "Vote in poll"))
                    }
                    .font(.subheadline)
                } else {
                    Text("Vote in the official app")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .task { webSignIn = await app.secureStore.authMode() == "web" }
        }
    }
}

/// A post's text with the images / GIFs / videos in it shown inline (uploaded ones via
/// `media_metadata`, and linked i.redd.it / preview.redd.it / v.redd.it / imgur …),
/// as comments do: they used to show as bare links.
private struct PostBodyView: View {
    let post: Post

    var body: some View {
        if !post.selftext.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bodySegments(post.selftext, post.bodyMedia, CommentBody.maxPostMedia).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let markdown): RedditMarkdown(text: markdown, media: post.bodyMedia, selectable: true)
                    case .media(let uri): CommentMediaView(uri: uri)
                    }
                }
            }
        }
    }
}

/// Translate: with one language to offer, a toggle (it / the original);
/// with two (the phone's and Settings → Second language), a menu.
struct TranslateButton: View {
    let targets: [String]
    let shownIn: String?
    let busy: Bool
    let onPick: (String?) -> Void

    var body: some View {
        Group {
            if busy {
                ProgressView().controlSize(.small)
            } else if targets.count > 1 {
                Menu {
                    ForEach(targets, id: \.self) { t in
                        Button {
                            onPick(t)
                        } label: {
                            if t == shownIn {
                                Label("Translate to \(Translate.languageName(t))", systemImage: "checkmark")
                            } else {
                                Text("Translate to \(Translate.languageName(t))")
                            }
                        }
                    }
                    if shownIn != nil {
                        Button("Show original") { onPick(nil) }
                    }
                } label: { icon }
            } else {
                Button {
                    onPick(shownIn != nil ? nil : targets.first)
                } label: { icon }
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: some View {
        Image(systemName: "translate")
            .foregroundStyle(shownIn != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 40, height: 40)
            .contentShape(.rect)
            .accessibilityLabel(shownIn != nil ? "Show original" : "Translate")
    }
}
