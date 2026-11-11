import SwiftUI
import UIKit

/// Scrollable list of posts for a feed key ('' = frontpage, subreddit name, or
/// `m::user::name`). `header` is rendered as the first scrolling item (e.g. a big title).
/// Put it directly under a `NavigationStack`: the screen's large title and the tab bar
/// follow its scrolling.
struct PostListView<Header: View>: View {
    let feedKey: String
    let header: (() -> Header)?
    var fabScroll: FabScroll? = nil
    /// Hosted by the Posts tab: its re-tap signal and Home's hidden subreddits apply.
    var postsTab = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var resumedOnce = false

    init(feedKey: String, postsTab: Bool = false, fabScroll: FabScroll? = nil, @ViewBuilder header: @escaping () -> Header) {
        self.feedKey = feedKey
        self.postsTab = postsTab
        self.fabScroll = fabScroll
        self.header = header
    }

    init(feedKey: String, postsTab: Bool = false, fabScroll: FabScroll? = nil, optionalHeader: (() -> Header)?) {
        self.feedKey = feedKey
        self.postsTab = postsTab
        self.fabScroll = fabScroll
        header = optionalHeader
    }

    var body: some View {
        // The controller, re-fetched after an account switch. Started right here (not
        // in a task) so the cached page can paint a frame sooner.
        let _ = app.feed.version
        let controller = app.feed.controller(feedKey)
        let _ = controller.start()
        let s = app.settings.value
        let isFrontpage = feedKey.isEmpty
        // With the Posts tab on r/all (Settings) the frontpage is a pushed page: plain, no For You / Blend / Home.
        let engines = s.postsTabAll ? nil : app.feed.engines
        let homeMode = isFrontpage && engines != nil && s.redditHomeAllowed && s.redditHomeFeed
        // Home and For You load behind the shuffling deck.
        let deckMode = isFrontpage && engines != nil && (homeMode || s.forYouFeed)
        let blendMode = isFrontpage && engines != nil && s.forYouFeed && s.blendHome && s.redditHomeAllowed
        let dismissible = deckMode
        let visibility = FeedVisibility(
            posts: controller.ui.state?.posts ?? [],
            seen: s.autoHideReadForYou && !homeMode ? app.history.ids : nil,
            hiddenIds: app.hiddenPosts.ids,
            dismissedIds: dismissible ? app.dismissedPosts.ids : [],
            hiddenSubs: isFrontpage || postsTab ? app.hiddenHomeSubs.ids : [],
            filters: app.contentFilters.value,
            viewing: feedKey.isEmpty || feedKey.hasPrefix("m::") ? nil : feedKey,
            crossposts: app.repository.crossposts.posts
        )
        PostCollection(model: PostListModel(
            controller: controller,
            ui: controller.ui,
            visibility: visibility,
            config: .current(),
            swipes: s.swipeActions ? (s.swipePostStart, s.swipePostEnd) : (.none, .none),
            frontpage: isFrontpage || postsTab,
            dismissible: dismissible,
            deckMode: deckMode,
            homeMode: homeMode,
            followsHome: homeMode || blendMode,
            homeStatus: homeMode ? engines?.homeStatus : nil,
            floatingChips: s.floatingChips,
            markReadOnScroll: s.markReadOnScroll && s.trackHistory,
            scrollSignal: postsTab ? app.navigator.frontpageScrollSignal : 0,
            header: header.map { make in AnyView(make()) },
            fabScroll: fabScroll
        ))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if controller.ui.state?.hasPending == true {
                NewPostsPill { controller.applyPending() }
                    .padding(.top, s.floatingChips ? 52 : 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: controller.ui.state?.hasPending == true)
        // Returning to the feed after a pushed route (e.g. a post) is popped, or to the
        // app: the frontpage keeps its posts for the "Keep feed for" time, then loads
        // anew; other feeds stage fresh posts behind a "New posts" pill once stale.
        // (The first appearance is this screen opening.)
        .onAppear {
            if resumedOnce {
                resume(controller)
            } else if !feedKey.isEmpty {
                controller.reloadIfOld()
            }
            resumedOnce = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resume(controller) }
        }
    }

    private func resume(_ controller: FeedController) {
        if feedKey.isEmpty { controller.refreshIfExpired() } else { controller.refreshIfStale() }
    }
}

extension PostListView where Header == EmptyView {
    init(feedKey: String, postsTab: Bool = false, fabScroll: FabScroll? = nil) {
        self.init(feedKey: feedKey, postsTab: postsTab, fabScroll: fabScroll, optionalHeader: nil)
    }
}

/// Tappable pill shown when a fresh feed page is staged after returning to a stale feed:
/// applies it and scrolls to top.
private struct NewPostsPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New posts", systemImage: "arrow.up").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glassProminent)
    }
}

/// Everything the collection needs from SwiftUI, for one update.
struct PostListModel {
    let controller: FeedController
    let ui: FeedUi
    let visibility: FeedVisibility
    let config: FeedRowConfig
    let swipes: (start: SwipeAction, end: SwipeAction)
    let frontpage: Bool
    let dismissible: Bool
    let deckMode: Bool
    let homeMode: Bool
    let followsHome: Bool
    let homeStatus: HomeStatus?
    let floatingChips: Bool
    let markReadOnScroll: Bool
    let scrollSignal: Int
    let header: AnyView?
    let fabScroll: FabScroll?
}

private struct PostCollection: UIViewRepresentable {
    let model: PostListModel

    func makeCoordinator() -> PostListCoordinator { PostListCoordinator(model: model) }

    func makeUIView(context: Context) -> UIView { context.coordinator.container }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.update(model)
    }
}

/// A `UICollectionView` that tells its screen it's the one to follow: the navigation bar's
/// large title and scroll edge, and the tab bar's minimizing, work from this.
final class ListScrollView: UICollectionView {
    var onWidthChange: (() -> Void)?
    var onWindowChange: ((Bool) -> Void)?
    /// Every layout pass, which a scroll view gets on every scrolled frame.
    var onLayout: (() -> Void)?
    private var lastWidth: CGFloat = 0
    /// Posted when a list enters a window, for `PagedListHook`.
    static let didAppear = Notification.Name("ListScrollView.didAppear")

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            // Not during layout: this can rebuild the rows.
            DispatchQueue.main.async { [weak self] in self?.onWidthChange?() }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
        guard window != nil else { return }
        NotificationCenter.default.post(name: ListScrollView.didAppear, object: self)
        var responder: UIResponder? = self
        while let r = responder, !(r is UIViewController) { responder = r.next }
        if let screen = responder as? UIViewController {
            screen.setContentScrollView(self, for: .top)
            screen.setContentScrollView(self, for: .bottom)
        }
    }
}

private enum FeedSection: Hashable { case header, feed }

private enum FeedItem: Hashable {
    case header
    case chips
    case status
    case post(String)
    case skeleton(Int)
    case deck
    case error
    case footer
}

/// The feed's list: `UICollectionView` with a diffable data source keyed by post id and
/// `UIHostingConfiguration` cells, so cells are really reused and a card's SwiftUI is only
/// asked to update. One collection view through every state (loading, error, posts), so
/// the refresh control, the chips and the scroll position never get rebuilt.
@MainActor final class PostListCoordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    let collectionView: ListScrollView
    /// The list with the chips over it: beside it rather than in it, as the scroll edge
    /// effect only reaches behind a view that's over its scroll view.
    let container = UIView()

    private var model: PostListModel
    private var dataSource: UICollectionViewDiffableDataSource<FeedSection, FeedItem>!
    private var rows: [String: PostRow] = [:]
    private var visibleIds: [String] = []
    private var lastVisibility: FeedVisibility?
    private var lastUiLoading = true
    private var visiblePosts: [Post] = []
    private var lastStyle: Style
    private var lastSignal: Int
    private var refreshing = false
    private let footer = FeedFooterModel()
    private var accent = IlayTheme.accent
    private var dwell = VisibilityDwell()
    private var dwellTimer: Timer?
    private var lastViewing: String?
    private var lastContentOffset: CGFloat = 0
    /// The one row of chips: a view over the list rather than a cell, since it's sometimes
    /// in the list's flow and sometimes floating. A blank `.chips` row keeps its place.
    private var chipsView: (UIView & UIContentView)?
    private let chipsState = FeedChipsState()
    private var chipsTracker = FloatingChipsTracker()
    private let chipsEdge = UIScrollEdgeElementContainerInteraction()
    /// The loading deck was just showing: deal the first cards in.
    private var dealing = false
    private var prefetched = Set<String>()
    /// The media browser opened from this list, told about each new page.
    private weak var browser: MediaBrowserModel?

    /// What changes every cell at once, and the chips.
    private struct Style: Equatable {
        let display: PostDisplay
        let seedColor: Int
        let textScale: Double
        let floatingChips: Bool
    }

    init(model: PostListModel) {
        self.model = model
        lastSignal = model.scrollSignal
        lastStyle = Style(display: model.config.display, seedColor: model.config.seedColor, textScale: model.config.textScale, floatingChips: model.floatingChips)
        // A placeholder layout: the real one needs self.
        collectionView = ListScrollView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init()
        collectionView.frame = container.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(collectionView)
        collectionView.collectionViewLayout = makeLayout()
        LeadingSwipeGate.install(on: collectionView) { [weak self] in self?.swipe(at: $0, leading: true) != nil }
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.allowsSelection = true
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        collectionView.refreshControl = refresh
        collectionView.onWidthChange = { [weak self] in
            guard let self else { return }
            update(self.model)
        }
        collectionView.onWindowChange = { [weak self] inWindow in self?.windowChanged(inWindow) }
        collectionView.onLayout = { [weak self] in self?.positionChips() }
        configureDataSource()
        // The shared video player, now rather than under the first video cell mid-scroll.
        _ = app.media.inlinePlayer
        update(model)
    }

    // MARK: Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else { return nil }
            let isFeed = dataSource.sectionIdentifier(for: sectionIndex) == .feed
            var list = UICollectionLayoutListConfiguration(appearance: .plain)
            list.backgroundColor = .clear
            list.headerMode = .none
            // Default and Mini are hairline-separated rows; the rest are cards.
            list.showsSeparators = isFeed && !model.config.isCarded
            list.itemSeparatorHandler = { [weak self] indexPath, config in
                var c = config
                c.topSeparatorVisibility = .hidden
                if case .post = self?.dataSource.itemIdentifier(for: indexPath) {
                    c.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0)
                } else {
                    c.bottomSeparatorVisibility = .hidden
                }
                return c
            }
            list.leadingSwipeActionsConfigurationProvider = { [weak self] in self?.swipe(at: $0, leading: true) }
            list.trailingSwipeActionsConfigurationProvider = { [weak self] in self?.swipe(at: $0, leading: false) }
            return NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
        }
    }

    private func swipe(at indexPath: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard case let .post(id) = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return nil }
        return PostSwipe.make(
            leading ? model.swipes.start : model.swipes.end,
            post: row.post, dismissible: model.dismissible, frontpage: model.frontpage,
            dark: collectionView.traitCollection.userInterfaceStyle == .dark
        )?.configuration
    }

    // MARK: Cells

    private func hosted<Content: View>(_ cell: UICollectionViewListCell, @ViewBuilder _ content: () -> Content) {
        let typeRange = IlayTheme.typeSize(app.settings.value.textScale).map { $0...$0 } ?? (.xSmall ... .accessibility5)
        cell.contentConfiguration = UIHostingConfiguration {
            content()
                .tint(accent)
                .dynamicTypeSize(typeRange)
        }
        .margins(.all, 0)
        .minSize(height: 0)
        cell.backgroundConfiguration = .clear()
    }

    private func configureDataSource() {
        // A pool per kind of media (Kotlin's contentType).
        let postCells = PostCellKind.allCases.map { _ in
            UICollectionView.CellRegistration<UICollectionViewListCell, PostRow> { [unowned self] cell, _, row in
                hosted(cell) { PostCard(row: row) }
                cell.configurationUpdateHandler = { cell, state in
                    // The system's press feedback for a row; a card fades a touch instead.
                    cell.contentView.alpha = state.isHighlighted && row.config.isCarded ? 0.7 : 1
                    var background = UIBackgroundConfiguration.clear()
                    background.backgroundColor = state.isHighlighted && !row.config.isCarded ? .systemFill : .clear
                    cell.backgroundConfiguration = background
                }
            }
        }
        let plain = UICollectionView.CellRegistration<UICollectionViewListCell, FeedItem> { [unowned self] cell, _, item in
            switch item {
            case .header:
                hosted(cell) { model.header.environment(AppNavigator.shared) }
            case .chips:
                // Where the row of chips sits while it's in the list (see positionChips).
                hosted(cell) { Color.clear.frame(height: chipsTracker.height) }
            case .status:
                hosted(cell) {
                    if let status = model.homeStatus {
                        HomeStatusStrip(status: status) { [weak self] in self?.pulledToRefresh() }
                    }
                }
            case .skeleton:
                hosted(cell) { PostSkeleton() }
            case .deck:
                hosted(cell) { app.feed.engines?.loadingDeck(forYou: !model.homeMode).padding(.top, 58) }
            case .error:
                if case let .error(error) = model.ui {
                    let (controller, key) = (model.controller, model.controller.key)
                    hosted(cell) { FeedErrorCell(error: error, controller: controller, feedKey: key) }
                }
            case .footer:
                hosted(cell) { FeedFooter(model: footer) }
            case .post:
                break
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [unowned self] view, indexPath, item in
            if case let .post(id) = item, let row = rows[id] {
                return view.dequeueConfiguredReusableCell(using: postCells[row.kind.rawValue], for: indexPath, item: row)
            }
            return view.dequeueConfiguredReusableCell(using: plain, for: indexPath, item: item)
        }
    }

    // MARK: Updates from SwiftUI

    func update(_ new: PostListModel) {
        let replacedController = model.controller !== new.controller
        model = new
        let width = collectionView.bounds.width
        var config = new.config
        if width > 0 { config.width = width }
        if replacedController { lastVisibility = nil }

        // Only what changed is worked out again: a body can re-run for many reasons.
        let configChanged = rows.values.first.map { $0.config != config } ?? false
        var visibleChanged = false
        if new.visibility != lastVisibility {
            lastVisibility = new.visibility
            visiblePosts = new.visibility.visible()
            visibleChanged = true
        }
        var reconfigure: [FeedItem] = []
        var reload: [FeedItem] = []
        if visibleChanged || configChanged {
            var next: [String: PostRow] = [:]
            next.reserveCapacity(visiblePosts.count)
            for post in visiblePosts {
                if let old = rows[post.id], old.post == post, old.config == config {
                    next[post.id] = old
                    continue
                }
                let row = PostRow(post, config: config)
                next[post.id] = row
                if let old = rows[post.id] {
                    // A post changing shape (Home's upgrades) needs a cell from another pool.
                    if old.kind == row.kind { reconfigure.append(.post(post.id)) } else { reload.append(.post(post.id)) }
                }
            }
            rows = next
            visibleIds = visiblePosts.map(\.id)
        }

        let style = Style(display: config.display, seedColor: config.seedColor, textScale: config.textScale, floatingChips: new.floatingChips)
        let styleChanged = style != lastStyle
        if styleChanged {
            lastStyle = style
            accent = IlayTheme.accent
        }
        collectionView.backgroundColor = config.isCarded ? .systemGroupedBackground : .systemBackground
        if styleChanged || replacedController || chipsView == nil { makeChips() }

        if collectionView.window != nil || new.controller.browseMedia == nil {
            new.controller.browseMedia = { [weak self] in self?.openMediaBrowser() }
        }
        browser?.feedChanged(visiblePosts, loaded: new.ui.state?.posts.count ?? 0)

        footer.loadingMore = new.ui.state?.loadingMore ?? false
        footer.hasMore = new.ui.state?.hasMore ?? false
        footer.hidden = new.visibility.posts.count - visibleIds.count

        // The list being replaced (sort / feed change): the new one starts at the top.
        let loading = new.ui.isLoading
        if loading && !lastUiLoading { scrollToTop(animated: false) }
        if loading && new.deckMode { dealing = true }
        lastUiLoading = loading

        applySnapshot(reconfigure: reconfigure, reload: reload, wholesale: styleChanged || replacedController)
        if styleChanged { collectionView.collectionViewLayout.invalidateLayout() }

        if new.scrollSignal != lastSignal {
            lastSignal = new.scrollSignal
            tabRetapped()
        }
        // Paging is triggered by reaching rows near the end. If the filters hide (almost)
        // everything loaded, there are no rows to reach and the list can't scroll, so the
        // feed stalled blank. Keep fetching instead, up to a bound in case nothing ever matches.
        if let s = new.ui.state, visibleIds.count < 10, s.hasMore, !s.loadingMore, s.posts.count < 250 {
            new.controller.loadMore()
        }
        // A new page arrived (or a cursor after an empty page) and the end is still in view.
        loadMoreIfNearEnd()
        updateDwellTimer()
    }

    private func applySnapshot(reconfigure: [FeedItem], reload: [FeedItem], wholesale: Bool) {
        let old = dataSource.snapshot()
        var snap = NSDiffableDataSourceSnapshot<FeedSection, FeedItem>()
        if model.header != nil {
            snap.appendSections([.header])
            snap.appendItems([.header], toSection: .header)
        }
        snap.appendSections([.feed])
        var items: [FeedItem] = [.chips]
        switch model.ui {
        case .loading:
            items += model.deckMode ? [.deck] : (0..<5).map { .skeleton($0) }
        case .error:
            items.append(.error)
        case .data:
            // Not your live Home: say what this is instead (until the next load works).
            switch model.homeStatus {
            case .saved, .fellBack: items.append(.status)
            default: break
            }
            items += visibleIds.map { .post($0) }
            items.append(.footer)
        }
        snap.appendItems(items, toSection: .feed)

        let oldItems = old.itemIdentifiers
        let present = Set(snap.itemIdentifiers)
        let oldSet = Set(oldItems)
        // These show what's in the model rather than a row: always up to date.
        let again = (reconfigure + [.header, .status, .error]).filter { present.contains($0) && oldSet.contains($0) }
        let anew = reload.filter { present.contains($0) && oldSet.contains($0) }
        if !wholesale && again.isEmpty && anew.isEmpty && oldItems == snap.itemIdentifiers { return }
        if !again.isEmpty { snap.reconfigureItems(again) }
        if !anew.isEmpty { snap.reloadItems(anew) }
        if wholesale {
            dataSource.applySnapshotUsingReloadData(snap)
            return
        }
        // A row or two going away (hide, dismiss, filter out) closes up as in Mail; anything
        // larger is a new list, not an animation.
        let removed = oldSet.subtracting(present)
        let added = present.subtracting(oldSet)
        let animate = added.isEmpty && !removed.isEmpty && removed.count <= 3 && collectionView.window != nil
        // A whole new list shares nothing with the cards on screen: don't drop in the
        // middle of it (returning to an expired feed loads anew, as on a fresh launch).
        let onScreen = collectionView.indexPathsForVisibleItems.compactMap { dataSource.itemIdentifier(for: $0) }.filter {
            if case .post = $0 { true } else { false }
        }
        let lostPlace = !onScreen.isEmpty && !onScreen.contains { present.contains($0) }
        dataSource.apply(snap, animatingDifferences: animate)
        if lostPlace { scrollToTop(animated: false) }
    }

    private func scrollToTop(animated: Bool) {
        let top = -collectionView.adjustedContentInset.top
        if collectionView.contentOffset.y > top {
            collectionView.setContentOffset(CGPoint(x: 0, y: top), animated: animated)
        }
    }

    // MARK: Chips

    private func makeChips() {
        let (controller, state) = (model.controller, chipsState)
        let typeRange = IlayTheme.typeSize(app.settings.value.textScale).map { $0...$0 } ?? (.xSmall ... .accessibility5)
        let configuration = UIHostingConfiguration {
            FeedChips(controller: controller, state: state)
                .tint(accent)
                .dynamicTypeSize(typeRange)
        }
        .margins(.all, 0)
        .minSize(height: 0)
        if let chipsView {
            chipsView.configuration = configuration
        } else {
            let view = configuration.makeContentView()
            container.addSubview(view)
            chipsView = view
        }
        let fit = chipsView?.systemLayoutSizeFitting(
            CGSize(width: max(collectionView.bounds.width, 1), height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        chipsTracker.height = max((fit?.height ?? 0).rounded(.up), 44)
    }

    /// Puts the row where it belongs for this frame: never a second copy to keep in step,
    /// and nothing for SwiftUI to do (except for the outline, when it crosses its place).
    private func positionChips() {
        guard let view = chipsView else { return }
        let c = collectionView
        let top = c.safeAreaInsets.top
        let inset = c.adjustedContentInset
        chipsTracker.scrolled(
            to: c.contentOffset.y,
            min: -inset.top,
            max: max(-inset.top, c.contentSize.height + inset.bottom - c.bounds.height)
        )
        var rowY: CGFloat?
        if let indexPath = dataSource.indexPath(for: .chips), let cell = c.cellForItem(at: indexPath) {
            rowY = cell.frame.minY - c.contentOffset.y
        }
        // Off screen, it waits just above the bar: "no place" isn't a position for a frame.
        let y = max(chipsTracker.y(rowY: rowY, top: top, floats: model.floatingChips), top - chipsTracker.height)
        let alpha = chipsTracker.alpha(y: y, top: top)
        view.isHidden = alpha == 0
        view.alpha = alpha
        let frame = CGRect(x: 0, y: y, width: c.bounds.width, height: chipsTracker.height)
        if view.frame != frame { view.frame = frame }
        let floating = rowY.map { $0 < top } ?? true
        if chipsState.floating != floating {
            chipsState.floating = floating
            // The bar's scroll edge effect reaches behind the row only while it's over the
            // list: in its place, it would blur the large title above it.
            if floating {
                chipsEdge.scrollView = c
                chipsEdge.edge = .top
                view.addInteraction(chipsEdge)
            } else {
                view.removeInteraction(chipsEdge)
            }
        }
    }

    /// The row doesn't rest half way: it finishes the way you were going.
    private func settleChips() {
        let past = chipsState.floating && (collectionView.contentOffset.y > -collectionView.adjustedContentInset.top)
        guard chipsTracker.settle(past: past) else { return }
        UIView.animate(withDuration: 0.2) { self.positionChips() }
    }

    // MARK: Refresh and scroll to top

    @objc private func pulledToRefresh() {
        startRefresh(haptic: true)
    }

    private func startRefresh(haptic: Bool) {
        if refreshing {
            return
        }
        if haptic { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        refreshing = true
        let controller = model.controller
        Task { [weak self] in
            await controller.refresh()
            self?.refreshing = false
            self?.collectionView.refreshControl?.endRefreshing()
        }
    }

    /// Frontpage only: the "tap active tab" signal — scroll to top, or refresh (with a
    /// visible spinner) when already there. No list yet (loading / error): ignored.
    private func tabRetapped() {
        guard model.ui.state != nil else { return }
        let top = -collectionView.adjustedContentInset.top
        if collectionView.contentOffset.y - top > 20 {
            scrollToTop(animated: true)
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let refresh = collectionView.refreshControl, !refreshing {
                refresh.beginRefreshing()
                collectionView.setContentOffset(CGPoint(x: 0, y: top - refresh.bounds.height), animated: true)
            }
            startRefresh(haptic: false)
        }
    }

    // MARK: Paging

    /// Page early, 10 cards from the end: a fast flick covers several cards in less time
    /// than a page takes to arrive. Whether the last row on screen is that close.
    nonisolated static func isNearEnd(lastVisible: Int, total: Int, fromEnd: Int) -> Bool {
        total > 0 && lastVisible >= total - fromEnd
    }

    private func loadMoreIfNearEnd() {
        guard let s = model.ui.state, s.hasMore, !s.loadingMore else { return }
        guard let last = collectionView.indexPathsForVisibleItems.filter({ $0.section == collectionView.numberOfSections - 1 }).map(\.item).max() else { return }
        // 10 posts from the end = 11 rows counting the footer.
        if Self.isNearEnd(lastVisible: last, total: collectionView.numberOfItems(inSection: collectionView.numberOfSections - 1), fromEnd: 11) { model.controller.loadMore() }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.section == collectionView.numberOfSections - 1, Self.isNearEnd(lastVisible: indexPath.item, total: collectionView.numberOfItems(inSection: indexPath.section), fromEnd: 11) {
            model.controller.loadMore()
        }
        // The first cards after the loading deck are dealt in.
        if dealing, case let .post(id) = dataSource.itemIdentifier(for: indexPath), let i = visibleIds.prefix(3).firstIndex(of: id), !UIAccessibility.isReduceMotionEnabled {
            let t = [-6.0, 5.0, -3.0][i % 3] * .pi / 180
            cell.alpha = 0
            cell.transform = CGAffineTransform(translationX: 0, y: CGFloat(180 - 60 * i)).rotated(by: t).scaledBy(x: 0.85, y: 0.85)
            UIView.animate(withDuration: 0.6, delay: 0.1 * Double(i), options: [.curveEaseOut, .allowUserInteraction]) {
                cell.alpha = 1
                cell.transform = .identity
            }
            if i == 2 { dealing = false }
        }
    }

    // MARK: Prefetching

    // Warm the image cache for the cards just below the screen, with the same URL and
    // decode size the card asks for.
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard case let .post(id) = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { continue }
            for image in row.prefetch where prefetched.insert("\(image.pixels)|\(image.url.absoluteString)").inserted {
                ImageLoader.shared.prefetch(urls: [image.url], maxPixelSize: image.pixels)
            }
        }
    }

    // MARK: Scroll

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A new scroll starting near the end asks again (retrying a failed page).
        loadMoreIfNearEnd()
        lastContentOffset = scrollView.contentOffset.y
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settleChips() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settleChips() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settleChips() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let fab = model.fabScroll else { return }
        let y = scrollView.contentOffset.y
        fab.onScroll(available: lastContentOffset - y, userInput: scrollView.isTracking)
        lastContentOffset = y
    }

    // MARK: Context menu

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, case let .post(id) = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return nil }
        let (dismissible, frontpage) = (model.dismissible, model.frontpage)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            MainActor.assumeIsolated { postContextMenu(row.post, dismissible: dismissible, frontpage: frontpage) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false // The card's own tap: its inner buttons go first (see PostCard).
    }

    // MARK: Seen

    private func windowChanged(_ inWindow: Bool) {
        if !inWindow {
            dwellTimer?.invalidate()
            dwellTimer = nil
        } else {
            updateDwellTimer()
            // The feed's Browse media button opens from the list on screen (a feed can be open twice).
            model.controller.browseMedia = { [weak self] in self?.openMediaBrowser() }
        }
    }

    /// For You impressions (shown-but-never-opened posts get demoted on the next build),
    /// "mark read on scroll", and Home following the card on screen all need to know
    /// what was seen. A light look four times a second, only when one of them is on.
    private func updateDwellTimer() {
        let needed = collectionView.window != nil && (model.markReadOnScroll || model.followsHome || model.deckMode)
        if !needed {
            dwellTimer?.invalidate()
            dwellTimer = nil
        } else if dwellTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.dwellTick() } }
            timer.tolerance = 0.05
            // Common modes: the default mode doesn't run during a scroll.
            RunLoop.main.add(timer, forMode: .common)
            dwellTimer = timer
        }
    }

    private func dwellTick() {
        let view = collectionView
        let inset = view.adjustedContentInset
        let visible = view.bounds.inset(by: UIEdgeInsets(top: inset.top, left: 0, bottom: inset.bottom, right: 0))
        var fractions: [String: Double] = [:]
        var firstId: String?
        var firstY = CGFloat.infinity
        for cell in view.visibleCells {
            guard let indexPath = view.indexPath(for: cell), case let .post(id) = dataSource.itemIdentifier(for: indexPath) else { continue }
            let height = cell.frame.height
            guard height > 0 else { continue }
            let shown = cell.frame.intersection(visible).height
            // A card taller than the screen counts by the screen.
            fractions[id] = shown / min(height, visible.height)
            if shown > 0, cell.frame.minY < firstY {
                firstY = cell.frame.minY
                firstId = id
            }
        }
        let seen = dwell.update(fractions: fractions, now: CACurrentMediaTime())
        let settings = app.settings.value
        for id in seen {
            guard let post = rows[id]?.post else { continue }
            if post.feedReason != nil { app.feed.engines?.learner.impression(post) }
            // "Mark read on scroll": a card actually seen counts as read (history only —
            // no interest learning, which is for real engagement).
            if settings.markReadOnScroll, settings.trackHistory { app.history.markViewed(post) }
        }
        // Home (and Blend's Home posts): follow the card on screen in the hidden
        // reddit.com page, so Reddit's own "seen" tracking matches what was actually read
        // and the next load brings new posts. (Cards not on its page are ignored there.)
        if model.followsHome, let firstId, firstId != lastViewing {
            lastViewing = firstId
            app.feed.engines?.homeViewing(firstId)
        }
    }
}

// MARK: Media browser

extension PostListCoordinator {
    /// Browse media (#103): from the first media post at or below the post at the top of
    /// the screen (one more than half scrolled away doesn't count); back on the last post
    /// viewed when it closes.
    fileprivate func openMediaBrowser() {
        let view = collectionView
        let edge = view.bounds.minY + view.adjustedContentInset.top
        let topId = view.indexPathsForVisibleItems.sorted().compactMap { indexPath -> String? in
            guard case let .post(id) = dataSource.itemIdentifier(for: indexPath),
                  let frame = view.layoutAttributesForItem(at: indexPath)?.frame, frame.midY > edge else { return nil }
            return id
        }.first
        let browser = MediaBrowserModel(visible: visiblePosts, loaded: model.ui.state?.posts.count ?? 0, startId: topId, controller: model.controller) { [weak self] lastId in
            guard let self, let lastId, let indexPath = dataSource.indexPath(for: .post(lastId)) else { return }
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
            // The top sits under the floating chips: bring the card down by however much
            // of the row is showing, so its header stays visible.
            let chipsShowing = model.floatingChips ? chipsTracker.height + chipsTracker.shift : 0
            if chipsShowing > 0 { collectionView.contentOffset.y -= chipsShowing }
        }
        self.browser = browser
        browser.present()
    }
}

/// A feed that failed to load. A quarantined or gated subreddit: opt in right here.
private struct FeedErrorCell: View {
    let error: Error
    let controller: FeedController
    let feedKey: String

    @State private var canOptIn = false

    private var reason: String? { (error as? RedditApiException)?.reason }

    var body: some View {
        Group {
            if canOptIn, !feedKey.hasPrefix("m::"), let reason {
                ErrorView(message: error, onRetry: {
                    Task {
                        do {
                            try await app.repository.optInSubreddit(feedKey, reason: reason)
                            controller.retry()
                        } catch {
                            app.navigator.showActionError("opt in", error)
                        }
                    }
                }, retryLabel: "View anyway")
            } else {
                ErrorView(message: error, onRetry: controller.retry)
            }
        }
        .frame(height: 360)
        .task(id: reason) { canOptIn = await app.repository.canOptIn(reason) }
    }
}
