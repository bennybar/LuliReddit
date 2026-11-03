import UIKit

/// PhotoView's scale state: double-tap cycles initial → covering → original size →
/// initial; after a pinch it goes back to initial.
enum ScaleState {
    case initial, covering, originalSize, zoomed

    var next: ScaleState {
        switch self {
        case .initial: .covering
        case .covering: .originalSize
        case .originalSize, .zoomed: .initial
        }
    }
}

/// A full-resolution image with pinch / double-tap zoom and pan (the PhotoView behaviour
/// of the Flutter build): min scale = contained, max = 4 × covered. While not zoomed its
/// own panning is off, so the pager can page and the viewer can swipe-to-dismiss; while
/// zoomed, UIKit's nested scroll views hand a pan that hits the edge back to the pager.
final class ZoomableImage: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let broken = UIImageView(image: UIImage(systemName: "photo.badge.exclamationmark"))
    private var imageSize: CGSize?
    private var scaleState = ScaleState.initial
    private var loadTask: Task<Void, Never>?
    private var configuredFor = CGSize.zero
    /// A double-tap's animation is running: its end isn't a pinch's.
    private var stepping = false
    private(set) var isZoomed = false
    var onZoomChanged: (Bool) -> Void = { _ in }

    init(url: String) {
        super.init(frame: .zero)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        isScrollEnabled = false
        addSubview(imageView)
        spinner.color = .white
        spinner.startAnimating()
        addSubview(spinner)
        broken.tintColor = UIColor.white.withAlphaComponent(0.6)
        broken.isHidden = true
        addSubview(broken)
        guard let parsed = URL(string: url) else {
            showFailure()
            return
        }
        // Full size, animated if it is: GIFs play in the viewer.
        if let hit = ImageLoader.shared.cached(url: parsed, maxPixelSize: 0, animated: true) {
            show(hit)
        } else {
            loadTask = Task { [weak self] in
                let image = await ImageLoader.shared.image(url: parsed, maxPixelSize: 0, animated: true)
                guard let self, !Task.isCancelled else { return }
                if let image { self.show(image) } else { self.showFailure() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    private func show(_ image: UIImage) {
        spinner.stopAnimating()
        spinner.isHidden = true
        imageView.image = image
        // One zoom unit is one image pixel per point, PhotoView's "original size".
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        imageSize = size
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        configuredFor = .zero
        setNeedsLayout()
    }

    private func showFailure() {
        spinner.stopAnimating()
        spinner.isHidden = true
        broken.isHidden = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        broken.frame = CGRect(x: bounds.midX - 24, y: bounds.midY - 24, width: 48, height: 48)
        if bounds.size != configuredFor { configureZoom() }
    }

    /// Back to contained, for a new image or a new window size (rotation).
    private func configureZoom() {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        configuredFor = bounds.size
        let fit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        minimumZoomScale = fit
        maximumZoomScale = fit * max(coveringScale(fit: fit) * 4, 3)
        zoomScale = fit
        scaleState = .initial
        updateZoomed()
        centre()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    /// Relative to contained: the scale at which the image covers the whole screen.
    private func coveringScale(fit: CGFloat) -> CGFloat {
        guard let imageSize else { return 1 }
        return max(bounds.width / (imageSize.width * fit), bounds.height / (imageSize.height * fit))
    }

    /// The scale (relative to contained) for a PhotoView scale state, clamped to min/max.
    private func scale(for state: ScaleState) -> CGFloat {
        let fit = minimumZoomScale
        guard fit > 0 else { return 1 }
        let raw: CGFloat = switch state {
        case .initial, .zoomed: 1
        case .covering: coveringScale(fit: fit)
        case .originalSize: 1 / fit
        }
        return min(max(raw, 1), maximumZoomScale / fit)
    }

    /// PhotoView's nextScaleState: step through the cycle, skipping states that land on
    /// the current scale. Unlike PhotoView (which re-centres) it zooms into the tapped
    /// point, as Photos does.
    func doubleTapped(at point: CGPoint) {
        guard imageSize != nil else { return }
        func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
        let current = scaleState
        var next = current.next
        var nextScale = scale(for: next)
        if current != .zoomed {
            let original = scale(for: current)
            var previous: CGFloat
            nextScale = original
            next = current
            repeat {
                previous = nextScale
                next = next.next
                nextScale = scale(for: next)
            } while same(previous, nextScale) && next != current
            if same(original, nextScale) { return }
        }
        scaleState = next
        stepping = true
        let target = nextScale * minimumZoomScale
        if next == .initial {
            setZoomScale(target, animated: true)
        } else {
            let centre = imageView.convert(point, from: self)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            zoom(to: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    /// A page the pager has left starts over.
    func resetZoom() {
        guard zoomScale != minimumZoomScale else { return }
        zoomScale = minimumZoomScale
        scaleState = .initial
    }

    private func centre() {
        contentInset = UIEdgeInsets(
            top: max(0, (bounds.height - contentSize.height) / 2),
            left: max(0, (bounds.width - contentSize.width) / 2),
            bottom: 0,
            right: 0
        )
    }

    private func updateZoomed() {
        let zoomed = minimumZoomScale > 0 && zoomScale / minimumZoomScale > 1.01
        isScrollEnabled = zoomed
        guard zoomed != isZoomed else { return }
        isZoomed = zoomed
        onZoomChanged(zoomed)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        updateZoomed()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if stepping {
            stepping = false
            return
        }
        scaleState = scale / minimumZoomScale < 1.02 ? .initial : .zoomed
        if scaleState == .initial { zoomScale = minimumZoomScale }
    }
}

/// Only takes a mostly horizontal drag: anything else is the swipe-to-dismiss.
private final class PagerScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === panGestureRecognizer {
            let v = panGestureRecognizer.velocity(in: self)
            if abs(v.y) > abs(v.x) { return false }
        }
        return super.gestureRecognizerShouldBegin(gesture)
    }
}

/// The pages of the image and gallery viewers. A single image is a pager of one. Keeps
/// the neighbours loaded (Kotlin's `beyondViewportPageCount = 1`) and nothing further.
final class ZoomablePager: DismissableContentView, UIScrollViewDelegate {
    private let urls: [String]
    private let scroll = PagerScrollView()
    private var pages: [Int: ZoomableImage] = [:]
    private var index: Int
    private var laidOutFor = CGSize.zero
    private let onPageChanged: (Int) -> Void

    init(urls: [String], initialIndex: Int, state: DismissState, onPageChanged: @escaping (Int) -> Void) {
        self.urls = urls
        self.index = min(max(initialIndex, 0), urls.count - 1)
        self.onPageChanged = onPageChanged
        super.init(state: state)
        scroll.delegate = self
        scroll.isPagingEnabled = true
        scroll.isDirectionalLockEnabled = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceHorizontal = urls.count > 1
        contentRoot.addSubview(scroll)
        // A swipe from the very edge is the back gesture, not a page.
        scroll.panGestureRecognizer.require(toFail: edgePan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard let page = pages[index] else { return }
        page.doubleTapped(at: gesture.location(in: page))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard contentRoot.bounds.size != laidOutFor, contentRoot.bounds.width > 0 else { return }
        laidOutFor = contentRoot.bounds.size
        // Rotation: same page, new geometry. Setting the offset below mustn't read as a swipe.
        scroll.delegate = nil
        scroll.frame = contentRoot.bounds
        scroll.contentSize = CGSize(width: laidOutFor.width * CGFloat(urls.count), height: laidOutFor.height)
        scroll.contentOffset = CGPoint(x: laidOutFor.width * CGFloat(index), y: 0)
        scroll.delegate = self
        for (i, page) in pages { page.frame = frame(ofPage: i) }
        tile()
    }

    private func frame(ofPage i: Int) -> CGRect {
        CGRect(x: laidOutFor.width * CGFloat(i), y: 0, width: laidOutFor.width, height: laidOutFor.height)
    }

    private func tile() {
        let wanted = max(index - 1, 0)...min(index + 1, urls.count - 1)
        for (i, page) in pages where !wanted.contains(i) {
            page.removeFromSuperview()
            pages[i] = nil
        }
        for i in wanted where pages[i] == nil {
            let page = ZoomableImage(url: urls[i])
            page.frame = frame(ofPage: i)
            page.onZoomChanged = { [weak self] zoomed in
                if let self, i == self.index { self.state.zoomed = zoomed }
            }
            scroll.addSubview(page)
            pages[i] = page
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard laidOutFor.width > 0 else { return }
        let page = min(max(Int((scrollView.contentOffset.x / laidOutFor.width).rounded()), 0), urls.count - 1)
        guard page != index else { return }
        index = page
        state.zoomed = pages[page]?.isZoomed ?? false
        onPageChanged(page)
        tile()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        for (i, page) in pages where i != index { page.resetZoom() }
    }
}
