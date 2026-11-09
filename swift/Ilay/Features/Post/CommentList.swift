import SwiftUI

/// Everything the comment list shows. Built in the screen's body; [revision] and the
/// other cheap fields say whether anything actually changed.
struct ThreadListContent {
    var revision = 0
    var post: Post?
    /// The post as just fetched with its comments, not the feed's copy shown while loading.
    var fresh = false
    var thread: PostThread?
    var loading = true
    var since: Int?
    var me = ""
    var currentMatchId: String?
    var translation = PostHeaderTranslate()
    var settings: Settings

    func sameAs(_ o: ThreadListContent) -> Bool {
        revision == o.revision && post?.id == o.post?.id && fresh == o.fresh && since == o.since && me == o.me
            && currentMatchId == o.currentMatchId && settings == o.settings
    }
}

/// What the screen asks of the list. Ask through this, not the controller: it may not exist yet.
@MainActor final class ThreadListHandle {
    fileprivate weak var controller: CommentListController?

    /// The index of the row at the top of the list (row 0 is the post).
    var topIndex: Int { controller?.topVisibleIndex ?? 0 }

    /// Scrolls so the row sits [fraction] of the screen below the top.
    func scroll(to id: String, fraction: CGFloat = 0) { controller?.scroll(to: id, fraction: fraction) }
}

/// The thread's list: `UICollectionView`, a diffable source keyed by comment fullname,
/// and `UIHostingConfiguration` cells: SwiftUI rows with real cell reuse.
struct CommentListView: UIViewControllerRepresentable {
    let content: ThreadListContent
    let handle: ThreadListHandle
    let actions: ThreadActions
    let header: PostHeaderModel
    let onRefresh: () -> Void
    var refreshing = false
    var extraTopInset: CGFloat = 0
    /// Folds the thread's floating buttons as the finger scrolls down.
    var fabScroll: FabScroll? = nil

    func makeUIViewController(context: Context) -> CommentListController {
        let c = CommentListController(actions: actions, header: header, onRefresh: onRefresh)
        handle.controller = c
        c.extraTopInset = extraTopInset
        c.fabScroll = fabScroll
        return c
    }

    func updateUIViewController(_ c: CommentListController, context: Context) {
        handle.controller = c
        c.update(content, refreshing: refreshing)
    }
}

private enum RowId {
    static let header = "\u{1}header"
    static let status = "\u{1}status"
}

/// A comment's cell: depth guides and the vote edge are bare layers. No backing store
/// or layout pass, and thousands of rows never redraw them.
private final class CommentCell: UICollectionViewListCell {
    private let backdrop = UIView()
    /// Calm: one container per top-level thread, drawn as contiguous rows whose first
    /// and last round its top and bottom.
    ///
    /// A Liquid Glass platter, drawn per row so a thread stays one seamless card (the
    /// system glass effect would put its own rounded edge on every row): a floating
    /// shadow, a hairline, a specular rim lit at the thread's top-left and bottom-right,
    /// and light falling on its top. It's pre-rendered (`piece`) per width and appearance
    /// into the thread's top row, a middle row, its bottom row and a one-row thread, which
    /// stretch to a row's height: masked shadows and gradients drawn live cost several
    /// offscreen passes a row while scrolling.
    private let card = CALayer()
    private let highlight = UIView()
    private static let radius: CGFloat = 32
    /// Room around the card in a piece for its shadow.
    private static let pad: CGFloat = 44
    private static let padBottom: CGFloat = 60
    /// The light on the glass's top fades out over this much of the first row.
    private static let sheenHeight: CGFloat = 80
    private static var pieces: [String: CGImage] = [:]
    private var calm = false
    private var dark = false
    private var first = false
    private var last = false
    private var guides: [CALayer] = []
    /// Settings → Mark comments you voted on (#122): the vote's colour glowing softly
    /// from the row's top corner on the end side, gone by its bottom edge.
    private let voteEdge = CAGradientLayer()
    private var depth = 0
    private var opLevel: Int?
    /// Where the row's name line ends (`CommentRowView` reports it).
    var headerBottom: CGFloat = 34

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = nil
        backgroundView = backdrop
        highlight.layer.cornerRadius = Self.radius
        highlight.layer.cornerCurve = .continuous
        backdrop.layer.addSublayer(card)
        backdrop.addSubview(highlight)
        backdrop.layer.addSublayer(voteEdge)
        voteEdge.type = .radial
        voteEdge.locations = [0, 0.45, 1]
        voteEdge.masksToBounds = true
        voteEdge.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ row: CommentRowModel, _ env: ThreadRowEnv, voteColor: UIColor?, accent: UIColor) {
        calm = env.calm
        dark = env.dark
        first = row.first
        last = row.last
        card.isHidden = !env.calm
        highlight.isHidden = !env.calm || !row.highlighted
        highlight.backgroundColor = accent.withAlphaComponent(0.16)
        var corners: CACornerMask = []
        if row.first { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if row.last { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        highlight.layer.maskedCorners = corners
        let shown = env.calm ? min(max(row.comment.depth, 0), 8) : 0
        while guides.count < shown {
            let l = CALayer()
            backdrop.layer.addSublayer(l)
            guides.append(l)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, l) in guides.enumerated() {
            l.isHidden = i >= shown
            if i < shown {
                // One quiet colour; OP's own rail takes the accent.
                let color = row.isOp && i == shown - 1 ? accent.withAlphaComponent(0.55) : .systemGray3
                l.backgroundColor = color.resolvedColor(with: traitCollection).cgColor
            }
        }
        voteEdge.isHidden = voteColor == nil
        if let c = voteColor?.resolvedColor(with: traitCollection) {
            voteEdge.colors = [c.withAlphaComponent(0.34).cgColor, c.withAlphaComponent(0.10).cgColor, c.withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
        depth = shown
        setNeedsLayout()
    }

    /// The platter for a row [height] tall: stretched from a short render through its
    /// one-point middle line, or drawn at the row's own height when it's shorter than the
    /// stretchable piece (a collapsed or one-line thread). Returns the image and the
    /// line to stretch (nil: none).
    private static func piece(width: CGFloat, height: CGFloat, first: Bool, last: Bool, dark: Bool, scale: CGFloat) -> (CGImage, CGFloat?) {
        let topCap = first ? sheenHeight : 0
        let bottomCap = last ? radius : 0
        let stretches = height >= topCap + 1 + bottomCap
        let h = stretches ? topCap + 1 + bottomCap : height
        let key = "\(width) \(h) \(first) \(last) \(dark) \(scale)"
        let top = first ? pad : 0
        let stretchLine: CGFloat? = stretches ? top + topCap : nil
        if let hit = pieces[key] { return (hit, stretchLine) }
        let size = CGSize(width: width + pad * 2, height: top + h + (last ? padBottom : 0))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            let cardRect = CGRect(x: pad, y: top, width: width, height: h)
            // A row that isn't the thread's top or bottom runs past its edges, so they stay
            // straight and the shadow keeps full strength right to the join.
            let over: CGFloat = 200
            let shape = CGRect(x: cardRect.minX, y: first ? cardRect.minY : cardRect.minY - over, width: width,
                               height: h + (first ? 0 : over) + (last ? 0 : over))
            func outline(_ inset: CGFloat) -> CGPath {
                UIBezierPath(roundedRect: shape.insetBy(dx: inset, dy: inset), cornerRadius: radius - inset).cgPath
            }
            // Opaque, so the shadow under it never shows through.
            let fill = dark ? UIColor(white: 0.16, alpha: 1) : .white
            if !dark {
                for (opacity, blur, y) in [(0.10, 44.0, 10.0), (0.05, 4, 1)] as [(CGFloat, CGFloat, CGFloat)] {
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: UIColor(white: 0, alpha: opacity).cgColor)
                    ctx.addPath(outline(0))
                    ctx.setFillColor(fill.cgColor)
                    ctx.fillPath()
                    ctx.restoreGState()
                }
            }
            ctx.addPath(outline(0))
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
            if first {
                ctx.saveGState()
                ctx.addPath(outline(0))
                ctx.clip()
                let colors = [UIColor(white: 1, alpha: dark ? 0.08 : 0.9).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: nil)!
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: cardRect.minY), end: CGPoint(x: 0, y: cardRect.minY + sheenHeight), options: [])
                ctx.restoreGState()
            }
            ctx.addPath(outline(0.25))
            ctx.setStrokeColor(UIColor(white: 0, alpha: dark ? 0.4 : 0.07).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokePath()
            // The specular rim: bright at the thread's top-left and bottom-right, across the
            // row's shape (with 60 past a joined edge, as the light falls on the whole card).
            ctx.saveGState()
            ctx.addPath(outline(1))
            ctx.setLineWidth(1.5)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            let bright = UIColor(white: 1, alpha: dark ? 0.55 : 1).cgColor
            let dim = UIColor(white: 1, alpha: dark ? 0.08 : 0.2).cgColor
            let colors = [first ? bright : dim, dim, last ? bright : dim] as CFArray
            let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: nil)!
            let lit = CGRect(x: cardRect.minX, y: first ? cardRect.minY : cardRect.minY - 60, width: width,
                             height: h + (first ? 0 : 60) + (last ? 0 : 60))
            ctx.translateBy(x: lit.minX, y: lit.minY)
            ctx.scaleBy(x: lit.width, y: lit.height)
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1, y: 1), options: [])
            ctx.restoreGState()
        }.cgImage!
        // Exact-height renders vary with the row: keep the cache from growing without end.
        if pieces.count > 64 { pieces.removeAll() }
        pieces[key] = image
        return (image, stretchLine)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = backdrop.bounds
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let width: CGFloat = 2
        // 12 side margin, and the 10 gap to the next thread under its last row.
        let cardFrame = CGRect(x: 12, y: 0, width: max(bounds.width - 24, 0), height: max(bounds.height - (last ? 10 : 0), 0))
        let top = 8 + (first ? 5 : 0) as CGFloat
        let bottom = cardFrame.maxY - (last ? 5 : 0) - 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = cardFrame
        if calm, cardFrame.width > 0, cardFrame.height > 0 {
            let (image, stretchLine) = Self.piece(width: cardFrame.width, height: cardFrame.height, first: first, last: last,
                                                  dark: dark, scale: max(traitCollection.displayScale, 1))
            let imageHeight = CGFloat(image.height) / max(traitCollection.displayScale, 1)
            card.contents = image
            card.contentsScale = max(traitCollection.displayScale, 1)
            card.contentsCenter = stretchLine.map { CGRect(x: 0, y: $0 / imageHeight, width: 1, height: 1 / imageHeight) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            card.frame = CGRect(x: cardFrame.minX - Self.pad, y: first ? -Self.pad : 0, width: cardFrame.width + Self.pad * 2,
                                height: cardFrame.height + (first ? Self.pad : 0) + (last ? Self.padBottom : 0))
        }
        for i in 0..<min(depth, guides.count) {
            let x = 12 + 12 + CGFloat(i) * 10 + 4
            guides[i].frame = CGRect(x: rtl ? bounds.width - x - width : x, y: top, width: width, height: max(bottom - top, 0))
        }
        // The glow fills the row's card (the whole row outside Calm), rounded where the card is.
        let glow = calm ? cardFrame : bounds
        voteEdge.frame = glow
        voteEdge.cornerRadius = calm ? Self.radius : 0
        var glowCorners: CACornerMask = []
        if first { glowCorners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if last { glowCorners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        voteEdge.maskedCorners = glowCorners
        if glow.width > 0, glow.height > 0 {
            let r = max(min(glow.height, glow.width * 0.9), 1)
            voteEdge.startPoint = CGPoint(x: rtl ? 0 : 1, y: 0)
            voteEdge.endPoint = CGPoint(x: rtl ? r / glow.width : 1 - r / glow.width, y: r / glow.height)
        }
        CATransaction.commit()
    }
}

final class CommentListController: UIViewController, UICollectionViewDelegate {
    private let actions: ThreadActions
    var fabScroll: FabScroll?
    private var lastContentOffset: CGFloat = 0
    private let header: PostHeaderModel
    private let onRefresh: () -> Void

    var extraTopInset: CGFloat = 0
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var last: ThreadListContent?
    private var rows: [String: CommentRowModel] = [:]
    private var ids: [String] = []
    private var env = ThreadRowEnv()
    private var statusText: String?
    private var lastCollapsed = Set<String>()
    // A scroll under way: the row and where it should end up. Rows not measured yet
    // have an estimated height, so the first try lands near it and the next corrects it.
    private var scrollTarget: (id: String, fraction: CGFloat, tries: Int)?

    init(actions: ThreadActions, header: PostHeaderModel, onRefresh: @escaping () -> Void) {
        self.actions = actions
        self.header = header
        self.onRefresh = onRefresh
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewCompositionalLayout { [unowned self] _, layoutEnv in
            NSCollectionLayoutSection.list(using: listConfiguration(), layoutEnvironment: layoutEnv)
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        collectionView.allowsSelection = false
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .always
        LeadingSwipeGate.install(on: collectionView) { [unowned self] in swipeConfiguration($0, last?.settings.swipeCommentStart) != nil }
        // Room for the floating buttons, so the last comment clears them.
        collectionView.contentInset.bottom = 72
        collectionView.contentInset.top = extraTopInset
        collectionView.selfSizingInvalidation = .enabled
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [unowned self] _ in onRefresh() }, for: .valueChanged)
        collectionView.refreshControl = refresh
        view.addSubview(collectionView)

        let commentCell = UICollectionView.CellRegistration<CommentCell, String> { [unowned self] cell, _, id in
            guard let row = rows[id] else { return }
            let colors = IlayTheme.voteColors(dark: env.dark)
            let edge: Color? = !env.voteEdge ? nil : row.comment.likes == true ? colors.up : row.comment.likes == false ? colors.down : nil
            cell.apply(row, env, voteColor: edge.map { UIColor($0) }, accent: UIColor(env.accent))
            cell.contentConfiguration = UIHostingConfiguration {
                CommentRowView(row: row, env: env, actions: actions) { [weak cell] in cell?.headerBottom = $0 }
            }
            .margins(.all, 0)
            .minSize(height: 0)
        }
        let moreCell = UICollectionView.CellRegistration<CommentCell, String> { [unowned self] cell, _, id in
            guard let row = rows[id] else { return }
            cell.apply(row, env, voteColor: nil, accent: UIColor(env.accent))
            cell.contentConfiguration = UIHostingConfiguration { MoreRowView(row: row, env: env, actions: actions) }
                .margins(.all, 0)
                .minSize(height: 0)
        }
        let headerCell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [unowned self] cell, _, _ in
            cell.backgroundConfiguration = .clear()
            let (post, fresh, translate, env) = (last?.post, last?.fresh ?? false, last?.translation ?? PostHeaderTranslate(), env)
            let model = header
            cell.contentConfiguration = UIHostingConfiguration {
                if let post { PostHeaderView(listed: post, fresh: fresh, translate: translate, model: model).threadCellTheme(env) }
            }
            .margins(.all, 0)
            .minSize(height: 0)
        }
        let statusCell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [unowned self] cell, _, _ in
            cell.backgroundConfiguration = .clear()
            let text = statusText
            cell.contentConfiguration = UIHostingConfiguration {
                Group {
                    if let text { Text(text).foregroundStyle(.secondary) } else { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
            .margins(.all, 0)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [unowned self] view, indexPath, id in
            switch id {
            case RowId.header: return view.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: id)
            case RowId.status: return view.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: id)
            default:
                if rows[id]?.comment.isMore == true { return view.dequeueConfiguredReusableCell(using: moreCell, for: indexPath, item: id) }
                return view.dequeueConfiguredReusableCell(using: commentCell, for: indexPath, item: id)
            }
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: CommentListController, _: UITraitCollection) in
            if let last = self.last {
                self.last = nil
                self.update(last, refreshing: false)
            }
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // The bars' scroll edge effect follows this list, as UIKit can't find it through SwiftUI.
        var p = parent
        while let host = p {
            host.setContentScrollView(collectionView, for: .top)
            host.setContentScrollView(collectionView, for: .bottom)
            p = host.parent
        }
    }

    private func listConfiguration() -> UICollectionLayoutListConfiguration {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = .clear
        config.showsSeparators = false
        // Swipes like Mail's: a short swipe shows the action, a full one runs it.
        config.leadingSwipeActionsConfigurationProvider = { [unowned self] in swipeConfiguration($0, last?.settings.swipeCommentStart) }
        config.trailingSwipeActionsConfigurationProvider = { [unowned self] in swipeConfiguration($0, last?.settings.swipeCommentEnd) }
        return config
    }

    private func swipeConfiguration(_ indexPath: IndexPath, _ action: SwipeAction?) -> UISwipeActionsConfiguration? {
        guard last?.settings.swipeActions == true, let action,
              let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], !row.comment.isMore,
              let spec = actions.swipe(action, row.comment, IlayTheme.voteColors(dark: env.dark)) else { return nil }
        let run = spec.run
        let contextual = UIContextualAction(style: .normal, title: nil) { _, _, done in
            done(true)
            // After the row has started closing: a reply opens a sheet over it.
            DispatchQueue.main.async { run() }
        }
        contextual.backgroundColor = spec.color
        contextual.image = UIImage(systemName: action.icon)
        contextual.accessibilityLabel = action.label
        let config = UISwipeActionsConfiguration(actions: [contextual])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    // MARK: Updates

    func update(_ content: ThreadListContent, refreshing: Bool) {
        loadViewIfNeeded()
        if !refreshing, collectionView.refreshControl?.isRefreshing == true { collectionView.refreshControl?.endRefreshing() }
        if let last, last.sameAs(content) { return }
        let previous = last
        last = content

        let s = content.settings
        let newEnv = ThreadRowEnv(
            calm: s.calmComments, tapToCollapse: s.tapToCollapse, voteEdge: s.voteEdge,
            dark: traitCollection.userInterfaceStyle == .dark, textScale: s.textScale, accent: IlayTheme.accent
        )
        let envChanged = newEnv != env
        env = newEnv
        view.backgroundColor = env.calm ? .systemBackground : .systemGroupedBackground
        collectionView.backgroundColor = .clear
        collectionView.tintColor = UIColor(env.accent)

        // Rows, keeping the first of any id a duplicate would crash the data source with.
        var newRows: [String: CommentRowModel] = [:]
        var newIds: [String] = []
        if content.post != nil { newIds.append(RowId.header) }
        let flat = content.thread?.flat ?? []
        newRows.reserveCapacity(flat.count)
        newIds.reserveCapacity(flat.count + 2)
        let thread = content.thread
        for (i, c) in flat.enumerated() where newRows[c.fullname] == nil {
            var row = rowModel(c, thread: thread, content: content)
            row.first = i == 0 || c.depth == 0
            row.last = i == flat.count - 1 || flat[i + 1].depth == 0
            newRows[c.fullname] = row
            newIds.append(c.fullname)
        }
        let newStatus: String? = content.thread == nil ? nil : flat.isEmpty ? "No comments yet" : nil
        if content.thread == nil || flat.isEmpty { newIds.append(RowId.status) }

        var changed: [String] = []
        // A "more" row's id is its first child's (Reddit names it t1_...), so loading the
        // replies turns that row into the comment itself. Different cell type, and UIKit
        // crashes on reconfiguring into another registration: those get a reload.
        var changedKind: [String] = []
        for (id, row) in newRows {
            guard let old = rows[id] else { continue }
            if old.comment.isMore != row.comment.isMore {
                changedKind.append(id)
            } else if old != row || envChanged {
                changed.append(id)
            }
        }
        let headerChanged = previous?.post != content.post || previous?.fresh != content.fresh || previous?.translation != content.translation || envChanged
        let statusChanged = statusText != newStatus
        let collapseChanged = (thread?.collapsed ?? []) != lastCollapsed
        let idsChanged = newIds != ids
        rows = newRows
        statusText = newStatus
        lastCollapsed = thread?.collapsed ?? []

        if !idsChanged, changed.isEmpty, changedKind.isEmpty, !headerChanged, !statusChanged { return }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(newIds)
        var reconfigure = changed
        if headerChanged, newIds.contains(RowId.header), ids.contains(RowId.header) { reconfigure.append(RowId.header) }
        if statusChanged, newIds.contains(RowId.status), ids.contains(RowId.status) { reconfigure.append(RowId.status) }
        if !reconfigure.isEmpty { snapshot.reconfigureItems(reconfigure) }
        if !changedKind.isEmpty { snapshot.reloadItems(changedKind) }
        ids = newIds

        if collapseChanged, idsChanged, previous?.thread != nil {
            // Collapsing and expanding animate. A comment collapsed from its bottom keeps
            // its name in view, rather than leaving the reader somewhere further down.
            let toggled = changed.first
            dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
                guard let self, let toggled, let index = dataSource.indexPath(for: toggled),
                      let frame = collectionView.layoutAttributesForItem(at: index)?.frame else { return }
                let top = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
                if frame.minY < top { scroll(to: toggled, fraction: 0) }
            }
        } else if idsChanged, previous?.thread != nil {
            // The full page, a refresh, a more-replies splice or a reply: the row at the
            // top of the screen stays exactly where it is, whatever changed above it.
            applyKeepingPosition(snapshot)
        } else {
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func rowModel(_ c: Comment, thread: PostThread?, content: ThreadListContent) -> CommentRowModel {
        let collapsed = thread?.collapsed ?? []
        let isCollapsed = collapsed.contains(c.id)
        return CommentRowModel(
            comment: c.with { $0.replies = [] },
            collapsed: isCollapsed,
            foldedReplies: !isCollapsed && collapsed.contains(CommentTree.folded(c.id)) ? CommentTree.replyCount(c) : nil,
            isNew: isNewComment(c, since: content.since, me: content.me),
            isOwn: !content.me.isEmpty && c.author == content.me,
            isOp: c.author == content.post?.author && c.author != "[deleted]",
            highlighted: content.currentMatchId == c.fullname,
            loading: thread?.loadingMore.contains(c.fullname) == true
        )
    }

    private func applyKeepingPosition(_ snapshot: NSDiffableDataSourceSnapshot<Int, String>) {
        let top = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let anchor = collectionView.indexPathsForVisibleItems
            .compactMap { path -> (id: String, y: CGFloat)? in
                guard let id = dataSource.itemIdentifier(for: path), let frame = collectionView.layoutAttributesForItem(at: path)?.frame, frame.maxY > top else { return nil }
                return (id, frame.minY)
            }
            .min { $0.y < $1.y }
        dataSource.apply(snapshot, animatingDifferences: false)
        guard let anchor, snapshot.indexOfItem(anchor.id) != nil, let path = dataSource.indexPath(for: anchor.id) else { return }
        collectionView.layoutIfNeeded()
        guard let frame = collectionView.layoutAttributesForItem(at: path)?.frame else { return }
        let delta = frame.minY - anchor.y
        if abs(delta) > 0.5 { collectionView.contentOffset.y += delta }
    }

    // MARK: Scrolling

    var topVisibleIndex: Int {
        guard let cv = collectionView else { return 0 }
        let y = cv.contentOffset.y + cv.adjustedContentInset.top + 1
        if let path = cv.indexPathForItem(at: CGPoint(x: cv.bounds.midX, y: y)) { return path.item }
        return cv.indexPathsForVisibleItems.map(\.item).min() ?? 0
    }

    func scroll(to id: String, fraction: CGFloat) {
        scrollTarget = (id, fraction, 0)
        runScroll()
    }

    private func targetOffset(_ id: String, fraction: CGFloat) -> CGFloat? {
        guard let path = dataSource.indexPath(for: id), let frame = collectionView.layoutAttributesForItem(at: path)?.frame else { return nil }
        let insets = collectionView.adjustedContentInset
        let visible = collectionView.bounds.height
        let wanted = frame.minY - insets.top - (visible - insets.top - insets.bottom) * fraction
        let maxY = max(collectionView.contentSize.height + insets.bottom - visible, -insets.top)
        return min(max(wanted, -insets.top), maxY)
    }

    private func runScroll() {
        guard let target = scrollTarget, let y = targetOffset(target.id, fraction: target.fraction) else {
            scrollTarget = nil
            return
        }
        if abs(collectionView.contentOffset.y - y) < 1 || target.tries >= 6 {
            scrollTarget = nil
            return
        }
        // Far away, an animated scroll would race through thousands of unmeasured rows
        // and land off target. Settle there first: each pass measures the rows
        // around the target, which moves it, until it stops moving.
        if target.tries == 0, abs(collectionView.contentOffset.y - y) > collectionView.bounds.height * 1.5 {
            scrollTarget = (target.id, target.fraction, 1)
            UIView.transition(with: collectionView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) { [self] in
                UIView.performWithoutAnimation {
                    for _ in 0..<12 {
                        guard let y = targetOffset(target.id, fraction: target.fraction), abs(collectionView.contentOffset.y - y) >= 1 else { break }
                        collectionView.contentOffset.y = y
                        collectionView.layoutIfNeeded()
                    }
                }
            }
            // The rows just above it measure once they're on screen, which moves it again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.runScroll() }
            return
        }
        scrollTarget = (target.id, target.fraction, target.tries + 1)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: y), animated: true)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { runScroll() }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollTarget = nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        fabScroll?.onScroll(available: lastContentOffset - y, userInput: scrollView.isTracking)
        lastContentOffset = y
    }

    // MARK: Long press

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, let id = dataSource.itemIdentifier(for: path), let row = rows[id], !row.comment.isMore else { return nil }
        // A long press on the name line collapses (see `CommentRowView.header`).
        if let cell = collectionView.cellForItem(at: path) as? CommentCell, collectionView.convert(point, to: cell).y < cell.headerBottom { return nil }
        let actions = actions
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { _ in
            UIMenu(children: actions.menu(row.comment, isOwn: row.isOwn))
        }
    }
}

/// Posted since your last visit to this thread.
func isNewComment(_ c: Comment, since: Int?, me: String) -> Bool {
    guard let since else { return false }
    return !c.isMore && c.author != me && c.createdUtc > since
}

/// Where to jump from the row at [topIndex]: the next hit below it, wrapping to the
/// first; backwards, the last one above, wrapping to the last. Row 0 is the post, so
/// comment `ci` is row `ci + 1`.
func jumpTarget(_ flat: [Comment], topIndex: Int, backwards: Bool = false, match: (Comment) -> Bool) -> Int? {
    let hits = flat.indices.filter { !flat[$0].isMore && match(flat[$0]) }.map { $0 + 1 }
    if hits.isEmpty { return nil }
    // Forward wraps to the first; backward stops at the top (nothing above: nil).
    return backwards ? hits.last { $0 < topIndex } : hits.first { $0 > topIndex } ?? hits.first
}
