import SwiftUI

/// A network image filling the slot its parent gives it (use `.frame` or
/// `.aspectRatio` from outside; it has no size of its own), decoded to that slot.
/// A still frame by default. Avatars and other images in a list must stay still:
/// some subreddit icons are animated GIFs, and every animated avatar redraws the
/// list on its own 25–33fps clock, out of step with the scroll, which drops frames.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// Plays GIF / WebP / APNG. For a viewer or an inline comment GIF, never for avatars.
    var animated = false
    /// The decode size in pixels, when the slot's isn't right (0 = full size). Defaults to the slot's.
    var maxPixelSize: Int? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let pixels = maxPixelSize ?? slotPixels(geo.size)
            // No request until the slot has been laid out, or it'd decode at the wrong size.
            LoadedImage(
                url: pixels > 0 || maxPixelSize != nil ? url : nil,
                maxPixelSize: pixels, contentMode: contentMode, animated: animated, placeholder: placeholder
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func slotPixels(_ size: CGSize) -> Int {
        // A filled slot crops: an image of another shape needs more than the slot's
        // longest side to still cover its shortest one.
        let wanted = max(size.width, size.height) * displayScale * (contentMode == .fill ? 1.5 : 1)
        // Whole steps, so near-identical slots share a cache entry.
        return Int((wanted / 64).rounded(.up)) * 64
    }
}

extension RemoteImage where Placeholder == Color {
    init(url: URL?, contentMode: ContentMode = .fill, animated: Bool = false, maxPixelSize: Int? = nil) {
        self.init(url: url, contentMode: contentMode, animated: animated, maxPixelSize: maxPixelSize) {
            Color(.secondarySystemFill)
        }
    }
}

private struct LoadedImage<Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: Int
    let contentMode: ContentMode
    let animated: Bool
    let placeholder: () -> Placeholder

    @State private var loaded: (key: String, image: UIImage)?

    private var key: String { "\(maxPixelSize)|\(url?.absoluteString ?? "")" }

    /// The loaded image, or straight from memory: a reused cell paints in its first frame.
    private var current: UIImage? {
        if let loaded, loaded.key == key { return loaded.image }
        return url.flatMap { ImageLoader.shared.cached(url: $0, maxPixelSize: maxPixelSize, animated: animated) }
    }

    var body: some View {
        ZStack {
            if let image = current {
                if animated, image.images != nil {
                    AnimatedImageView(image: image, contentMode: contentMode)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            guard let url, current == nil else { return }
            // Frame 0 first: decoding every frame of a GIF takes a while, and the
            // still is quick (and often already cached by a feed thumbnail).
            if animated, let still = await ImageLoader.shared.image(url: url, maxPixelSize: maxPixelSize),
               !Task.isCancelled {
                loaded = (key, still)
            }
            guard let image = await ImageLoader.shared.image(url: url, maxPixelSize: maxPixelSize, animated: animated),
                  !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { loaded = (key, image) }
        }
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        // The slot decides the size, not the image.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        if view.image !== image {
            view.image = image
        }
        // Animating GIFs redraw off-beat with the scroll: they hold still until it settles.
        if image.images != nil { PauseWhileScrolling.attach(view) }
    }
}
