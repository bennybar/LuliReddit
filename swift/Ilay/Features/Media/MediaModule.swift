import Foundation

/// Media singletons: the pooled feed video player.
///
/// Android's "Save media to" folder has no iOS form (Flutter's `MediaFolderController`
/// is always null here, and its Settings row Android-only): media saves to the "Ilay"
/// album in Photos, so `mediaFolderUri` / `mediaFolderName` are never read.
@MainActor final class MediaModule {
    /// The one AVPlayer shared by every inline feed video.
    let inlinePlayer = InlineVideoPool()

    init() {
        _ = VideoAudio.shared // Before any clip plays: see its comment.
    }
}
