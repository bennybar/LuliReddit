import SwiftUI
import UIKit

/// State of a `PagedSource`.
struct PagedState<T> {
    var items: [T] = []
    var after: String? = nil
    var loading = true
    var loadingMore = false
    var error: Error? = nil

    var hasMore: Bool { after?.isEmpty == false }
}

/// An infinite list backed by a `fetch(after)` callback. Held in `@State`, so it survives
/// navigating to a post and back.
@MainActor @Observable final class PagedSource<T> {
    private(set) var state = PagedState<T>()

    @ObservationIgnored private let fetch: (String?) async throws -> Listing<T>
    @ObservationIgnored private var lastLoaded = 0
    @ObservationIgnored private var loadJob: Task<Void, Never>?
    @ObservationIgnored private var moreJob: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(fetch: @escaping (String?) async throws -> Listing<T>) { self.fetch = fetch }

    func start() {
        if started { return }
        started = true
        load()
    }

    /// (Re)loads the first page. `silent` keeps the list (and position) on screen.
    @discardableResult func load(silent: Bool = false) -> Task<Void, Never> {
        loadJob?.cancel()
        // A page being fetched belongs to the old list: its rows and cursor
        // mustn't land on the new first page.
        moreJob?.cancel()
        moreJob = nil
        state.loadingMore = false
        if !silent {
            state.loading = true
            state.error = nil
        }
        let job = Task { [self] in
            do {
                let listing = try await fetch(nil)
                if Task.isCancelled { return }
                state = PagedState(items: listing.items, after: listing.after, loading: false)
                lastLoaded = nowMillis()
            } catch {
                if Task.isCancelled { return }
                // A silent (stale) refresh failing shouldn't blow away the list.
                if !silent {
                    state.error = error
                    state.loading = false
                }
            }
        }
        loadJob = job
        return job
    }

    /// Returning to this list after a pushed route is popped: silently refresh if the
    /// data has gone stale (no full-screen spinner, keeps the place).
    func refreshIfStale(maxAgeMillis: Int = 5 * 60_000) {
        if !state.loading && nowMillis() - lastLoaded > maxAgeMillis { load(silent: true) }
    }

    func loadMore() {
        let s = state
        if s.loading || s.loadingMore || !s.hasMore { return }
        state.loadingMore = true
        moreJob = Task { [self] in
            do {
                let listing = try await fetch(s.after)
                // Only onto the list this page continues (not one refreshed meanwhile).
                if Task.isCancelled || state.after != s.after { return }
                state.items += listing.items
                state.after = listing.after
                state.loadingMore = false
            } catch {
                if Task.isCancelled || state.after != s.after { return }
                state.loadingMore = false
            }
        }
    }
}

/// How a `PagedList` treats a row that is a post (or has one): the feed's swipes, long-press
/// menu and image prefetching. `swipes` replace Settings' (Saved: both sides unsave).
struct PagedPostRows<T> {
    let post: (T) -> Post?
    var swipes: ((Post) -> (leading: PostSwipe?, trailing: PostSwipe?))? = nil
}

/// Generic infinite-scroll list with pull-to-refresh, the feed's collection view for any
/// row. Rows are SwiftUI (`itemContent`) in reused cells. Each new `scrollTop` value
/// scrolls it to the top. Directly under a `NavigationStack`, bars follow it as they do `PostListView`.
struct PagedList<T, Content: View>: View {
    let source: PagedSource<T>
    let itemKey: (T) -> AnyHashable
    let emptyLabel: String
    /// The empty state's SF Symbol.
    let emptySymbol: String
    /// A pool of reused cells per value: rows that look alike (Kotlin's contentType).
    let contentType: ((T) -> Int)?
    /// How old the list may be before a return from a pushed route reloads it.
    let staleAfterMillis: Int
    let scrollTop: Int
    let posts: PagedPostRows<T>?
    let itemContent: (T) -> Content

    @State private var appeared = false

    init(
        source: PagedSource<T>,
        itemKey: @escaping (T) -> AnyHashable,
        emptyLabel: String = "Nothing here",
        emptySymbol: String = "tray",
        contentType: ((T) -> Int)? = nil,
        staleAfterMillis: Int = 5 * 60_000,
        scrollTop: Int = 0,
        posts: PagedPostRows<T>? = nil,
        @ViewBuilder itemContent: @escaping (T) -> Content
    ) {
        self.source = source
        self.itemKey = itemKey
        self.emptyLabel = emptyLabel
        self.emptySymbol = emptySymbol
        self.contentType = contentType
        self.staleAfterMillis = staleAfterMillis
        self.scrollTop = scrollTop
        self.posts = posts
        self.itemContent = itemContent
    }

    var body: some View {
        let state = source.state
        Group {
            if state.loading && state.items.isEmpty {
                Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.error {
                ErrorView(message: "Could not load.\n\(friendlyError(error))", onRetry: { source.load() })
            } else {
                PagedCollection(
                    source: source, items: state.items, itemKey: itemKey, contentType: contentType,
                    scrollTop: scrollTop, posts: posts, itemContent: itemContent
                )
                .ignoresSafeArea()
                .overlay {
                    // Over the list, so pull to refresh still works through it.
                    if state.items.isEmpty { ContentUnavailableView(emptyLabel, systemImage: emptySymbol).allowsHitTesting(false) }
                }
            }
        }
        .task { source.start() }
        // Only a return from a pushed route (as Flutter's didPopNext) — not the app
        // coming back to the foreground, which would replace the list under the user
        // and lose their place.
        .onAppear {
            if appeared { source.refreshIfStale(maxAgeMillis: staleAfterMillis) }
            appeared = true
        }
    }
}

private struct PagedCollection<T, Content: View>: UIViewRepresentable {
    let source: PagedSource<T>
    let items: [T]
    let itemKey: (T) -> AnyHashable
    let contentType: ((T) -> Int)?
    let scrollTop: Int
    let posts: PagedPostRows<T>?
    let itemContent: (T) -> Content

    func makeCoordinator() -> PagedCoordinator<T, Content> {
        PagedCoordinator(source: source, itemKey: itemKey, contentType: contentType, posts: posts, itemContent: itemContent, scrollTop: scrollTop)
    }

    func makeUIView(context: Context) -> ListScrollView { context.coordinator.collectionView }

    func updateUIView(_ view: ListScrollView, context: Context) {
        context.coordinator.update(source: source, items: items, posts: posts, itemContent: itemContent, scrollTop: scrollTop)
    }
}

private enum PagedItem: Hashable {
    case row(AnyHashable)
    case footer
}

@MainActor private final class PagedCoordinator<T, Content: View>: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    let collectionView: ListScrollView

    private var source: PagedSource<T>
    private let itemKey: (T) -> AnyHashable
    private let contentType: ((T) -> Int)?
    private var posts: PagedPostRows<T>?
    private var itemContent: (T) -> Content
    private var byKey: [AnyHashable: T] = [:]
    private var keys: [AnyHashable] = []
    private var lastItemsCount = -1
    private var lastScrollTop: Int
    private var dataSource: UICollectionViewDiffableDataSource<Int, PagedItem>!
    private var registrations: [Int: UICollectionView.CellRegistration<UICollectionViewListCell, T>] = [:]
    private lazy var plainRow = makeRegistration()
    private let footer = FeedFooterModel()

    init(source: PagedSource<T>, itemKey: @escaping (T) -> AnyHashable, contentType: ((T) -> Int)?, posts: PagedPostRows<T>?, itemContent: @escaping (T) -> Content, scrollTop: Int) {
        self.source = source
        self.itemKey = itemKey
        self.contentType = contentType
        self.posts = posts
        self.itemContent = itemContent
        lastScrollTop = scrollTop
        collectionView = ListScrollView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init()
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.backgroundColor = .clear
        list.showsSeparators = false
        list.leadingSwipeActionsConfigurationProvider = { [weak self] in self?.swipe($0, leading: true) }
        list.trailingSwipeActionsConfigurationProvider = { [weak self] in self?.swipe($0, leading: false) }
        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout.list(using: list)
        LeadingSwipeGate.install(on: collectionView) { [weak self] in self?.swipe($0, leading: true) != nil }
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.backgroundColor = .systemBackground
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulled), for: .valueChanged)
        collectionView.refreshControl = refresh

        // Registrations have to exist before the first dequeue: one pool per declared kind is made as seen.
        let footerCell = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [unowned self] cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration { FeedFooter(model: footer) }.margins(.all, 0).minSize(height: 0)
            cell.backgroundConfiguration = .clear()
        }
        _ = plainRow
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [unowned self] view, indexPath, item in
            switch item {
            case .footer:
                return view.dequeueConfiguredReusableCell(using: footerCell, for: indexPath, item: 0)
            case let .row(key):
                let value = byKey[key]!
                let registration = contentType.map { registrations[$0(value)] ?? plainRow } ?? plainRow
                return view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: value)
            }
        }
    }

    private func makeRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, T> {
        UICollectionView.CellRegistration { [unowned self] cell, _, value in
            let typeRange = IlayTheme.typeSize(app.settings.value.textScale).map { $0...$0 } ?? (.xSmall ... .accessibility5)
            cell.contentConfiguration = UIHostingConfiguration {
                itemContent(value)
                    .tint(IlayTheme.accent)
                    .dynamicTypeSize(typeRange)
                    .environment(AppNavigator.shared)
            }
            .margins(.all, 0)
            .minSize(height: 0)
            cell.backgroundConfiguration = .clear()
        }
    }

    func update(source: PagedSource<T>, items: [T], posts: PagedPostRows<T>?, itemContent: @escaping (T) -> Content, scrollTop: Int) {
        self.source = source
        self.posts = posts
        self.itemContent = itemContent
        // A pool per kind, made before anything dequeues from it (registering mid-dequeue is refused).
        if let contentType {
            for item in items {
                let kind = contentType(item)
                if registrations[kind] == nil { registrations[kind] = makeRegistration() }
            }
        }
        var seen = Set<AnyHashable>()
        var nextKeys: [AnyHashable] = []
        var nextByKey: [AnyHashable: T] = [:]
        nextKeys.reserveCapacity(items.count)
        for item in items {
            let key = itemKey(item)
            if seen.insert(key).inserted {
                nextKeys.append(key)
                nextByKey[key] = item
            }
        }
        let changed = nextKeys != keys
        keys = nextKeys
        byKey = nextByKey
        footer.loadingMore = source.state.loadingMore
        footer.hasMore = true
        if changed {
            var snap = NSDiffableDataSourceSnapshot<Int, PagedItem>()
            snap.appendSections([0])
            snap.appendItems(keys.map { .row($0) } + [.footer])
            dataSource.apply(snap, animatingDifferences: false)
        }
        if scrollTop != lastScrollTop {
            lastScrollTop = scrollTop
            collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
        }
        loadMoreIfNearEnd()
    }

    private func swipe(_ indexPath: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let post = post(at: indexPath), let posts else { return nil }
        if let custom = posts.swipes {
            let pair = custom(post)
            return (leading ? pair.leading : pair.trailing)?.configuration
        }
        let s = app.settings.value
        guard s.swipeActions else { return nil }
        return PostSwipe.make(
            leading ? s.swipePostStart : s.swipePostEnd, post: post, dismissible: false, frontpage: false,
            dark: collectionView.traitCollection.userInterfaceStyle == .dark
        )?.configuration
    }

    private func post(at indexPath: IndexPath) -> Post? {
        guard let posts, case let .row(key) = dataSource.itemIdentifier(for: indexPath), let value = byKey[key] else { return nil }
        return posts.post(value)
    }

    @objc private func pulled() {
        let source = source
        Task { [weak self] in
            await source.load().value
            self?.collectionView.refreshControl?.endRefreshing()
        }
    }

    /// Asks while the last visible row is within 4 rows of the end, whenever the loaded page
    /// changes and whenever a new scroll starts there (retrying a failed page): not only
    /// when the end first comes into view, which stalled short lists.
    private func loadMoreIfNearEnd() {
        guard let last = collectionView.indexPathsForVisibleItems.map(\.item).max() else { return }
        if PostListCoordinator.isNearEnd(lastVisible: last, total: keys.count + 1, fromEnd: 4) { source.loadMore() }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if PostListCoordinator.isNearEnd(lastVisible: indexPath.item, total: keys.count + 1, fromEnd: 4) { source.loadMore() }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { loadMoreIfNearEnd() }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let config = FeedRowConfig.current(width: collectionView.bounds.width)
        for indexPath in indexPaths {
            guard let post = post(at: indexPath) else { continue }
            for image in PostRow(post, config: config).prefetch {
                ImageLoader.shared.prefetch(urls: [image.url], maxPixelSize: image.pixels)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let post = post(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            MainActor.assumeIsolated { postContextMenu(post, dismissible: false, frontpage: false) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }
}
