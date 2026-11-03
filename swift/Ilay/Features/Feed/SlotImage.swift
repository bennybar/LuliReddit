import SwiftUI
import UIKit

/// A feed image for a slot of known size, decoded at `pixels` (the size the prefetcher
/// asked for, so it's a cache hit). A plain `UIImageView`, unlike `RemoteImage`: there's
/// no `GeometryReader` per cell, and an image arriving doesn't invalidate any SwiftUI
/// view, so it can't resize or re-lay out a cell while the list scrolls.
struct SlotImage: UIViewRepresentable {
    let url: URL?
    let pixels: Int
    /// What a failed load shows, instead of staying blank.
    var brokenSymbol: String? = nil

    func makeUIView(context: Context) -> SlotImageView { SlotImageView() }

    func updateUIView(_ view: SlotImageView, context: Context) {
        view.load(url: url, pixels: pixels, brokenSymbol: brokenSymbol)
    }

    /// The slot decides the size, never the image.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SlotImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class SlotImageView: UIImageView {
    private var key = ""
    private var requested: (url: URL, pixels: Int)?
    private var brokenSymbol: String?
    private var task: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = .secondarySystemFill
        tintColor = .secondaryLabel
        isUserInteractionEnabled = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func load(url: URL?, pixels: Int, brokenSymbol: String?) {
        let newKey = "\(pixels)|\(url?.absoluteString ?? "")"
        guard newKey != key else { return }
        key = newKey
        self.brokenSymbol = brokenSymbol
        task?.cancel()
        task = nil
        requested = url.map { ($0, pixels) }
        contentMode = .scaleAspectFill
        layer.removeAllAnimations()
        alpha = 1
        // Straight from memory: a reused cell paints in its first frame.
        image = url.flatMap { ImageLoader.shared.cached(url: $0, maxPixelSize: pixels) }
        if image == nil { fetch() }
    }

    private func fetch() {
        guard window != nil, task == nil, let requested else { return }
        task = Task { [weak self] in
            let loaded = await ImageLoader.shared.image(url: requested.url, maxPixelSize: requested.pixels)
            guard let self, !Task.isCancelled else { return }
            task = nil
            if let loaded {
                image = loaded
                alpha = 0
                UIView.animate(withDuration: 0.15) { self.alpha = 1 }
            } else if let brokenSymbol {
                contentMode = .center
                image = UIImage(systemName: brokenSymbol)
            }
        }
    }

    // Scrolled away unfinished: leave the flight (a prefetch of the same image keeps it
    // going), and ask again if it comes back.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            task?.cancel()
            task = nil
        } else if image == nil {
            fetch()
        }
    }
}
