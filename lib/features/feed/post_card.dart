import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets/tap_guard.dart';
import 'inline_video.dart';
import 'post_overrides.dart';
import '../../core/theme/app_theme.dart';
import '../../models/post.dart';
import '../history/history_store.dart';
import '../history/interest_store.dart';
import '../media/gallery_carousel.dart';
import '../media/media_viewers.dart';
import '../media/nsfw_blur.dart';
import '../post/post_actions.dart';
import '../settings/settings_controller.dart';
import 'swipe_actions.dart';

class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post});
  final Post post;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  // Vote / score / saved / comment-count live in the shared post-overrides
  // store (keyed by post id) so the card stays in sync with the post-detail
  // screen and survives scrolling.
  PostOverride get _ov =>
      ref.read(postOverridesProvider.notifier).effective(widget.post);

  Future<void> _vote(int dir) async {
    final overrides = ref.read(postOverridesProvider.notifier);
    final current = _ov.likes == true ? 1 : (_ov.likes == false ? -1 : 0);
    final target = current == dir ? 0 : dir;
    overrides.setVote(widget.post, target);
    // Learn: upvoting a community raises its affinity; downvoting lowers it.
    if (target == 1) {
      ref.read(interestStoreProvider.notifier).bump(widget.post.subreddit, 2);
      ref.read(keywordStoreProvider.notifier).bumpTitle(widget.post.title, 1);
    } else if (target == -1) {
      ref.read(interestStoreProvider.notifier).bump(widget.post.subreddit, -1.5);
      ref.read(keywordStoreProvider.notifier).bumpTitle(widget.post.title, -0.8);
    }
    try {
      await ref.read(redditRepositoryProvider).vote(widget.post.fullname, target);
    } catch (_) {
      overrides.setVote(widget.post, current); // revert
    }
  }

  Future<void> _toggleSave() async {
    final overrides = ref.read(postOverridesProvider.notifier);
    final next = !_ov.saved;
    overrides.setSaved(widget.post, next);
    ref.read(interestStoreProvider.notifier).bump(widget.post.subreddit, next ? 3 : -3);
    if (next) {
      ref.read(keywordStoreProvider.notifier).bumpTitle(widget.post.title, 1.5);
    }
    try {
      await ref.read(redditRepositoryProvider).setSaved(widget.post.fullname, next);
    } catch (_) {
      overrides.setSaved(widget.post, !next);
    }
  }

  void _openDetail() {
    Analytics.track('post_opened');
    if (ref.read(settingsControllerProvider).trackHistory) {
      ref.read(historyControllerProvider.notifier).markViewed(widget.post);
      ref.read(interestStoreProvider.notifier).bump(widget.post.subreddit, 0.5);
    }
    context.push(
      '/comments/${widget.post.subreddit}/${widget.post.id}',
      extra: widget.post,
    );
  }

  void _openMedia() {
    final p = widget.post;
    // Viewing media is engagement too (slightly stronger than a plain open).
    if (p.type != PostType.self &&
        ref.read(settingsControllerProvider).trackHistory) {
      ref.read(interestStoreProvider.notifier).bump(p.subreddit, 1);
    }
    switch (p.type) {
      case PostType.image:
      case PostType.gif:
        openImageViewer(context, p.previewUrl ?? p.url, title: p.title);
      case PostType.gallery:
        openGalleryViewer(context, p.gallery, title: p.title);
      case PostType.video:
        final src = p.hlsUrl ?? p.fallbackVideoUrl ?? resolveVideoUrl(p.url);
        openVideoViewer(context, src,
            title: p.title,
            downloadUrl: p.fallbackVideoUrl ?? resolveVideoUrl(p.url),
            externalUrl: p.url);
      case PostType.link:
        launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication);
      case PostType.self:
        _openDetail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final seen = ref.watch(historyContainsProvider(widget.post.id));
    Widget card = switch (settings.postDisplay) {
      PostDisplay.large => _largeCard(context),
      PostDisplay.card => _cardsCard(context),
      PostDisplay.mini => _miniCard(context),
    };
    // Dim already-viewed posts when history tracking is on.
    if (seen && settings.trackHistory) {
      card = Opacity(opacity: 0.55, child: card);
    }
    // "Why you're seeing this" banner (For You feed only).
    final reason = widget.post.feedReason;
    if (reason != null) {
      // Count the impression: shown-but-never-opened posts get demoted on the
      // next feed build (batched + deduped inside the store).
      ref.read(impressionStoreProvider.notifier).record(widget.post.id);
      final cs = Theme.of(context).colorScheme;
      card = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 8, 0),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 13, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary),
                  ),
                ),
                // Discoverable entry to the feed-tuning sheet (also on long-press)
                // so "show less from this subreddit" isn't hidden.
                InkWell(
                  onTap: _showTuneSheet,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded, size: 13, color: cs.primary),
                        const SizedBox(width: 4),
                        Text('Tune',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          card,
        ],
      );
    }
    return GestureDetector(
      onLongPress: _showTuneSheet,
      child: SwipeActions(
        enabled: settings.swipeActions,
        onRight: () => _vote(1),
        onLeft: () => _vote(-1),
        child: card,
      ),
    );
  }

  /// Long-press → "tune your feed": teach the on-device model faster.
  void _showTuneSheet() {
    HapticFeedback.mediumImpact();
    final sub = widget.post.subreddit;
    final muted = ref.read(mutedSubsProvider.notifier).contains(sub);
    final interest = ref.read(interestStoreProvider.notifier);
    void toast(String msg) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: 'Manage',
            onPressed: () => context.push('/manage_for_you'),
          ),
        ));

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      // Ignore taps briefly so the gesture that opened the sheet can't fall
      // through onto an item (which fired More/Less directly with no sheet).
      builder: (ctx) => TapGuard(
        child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 18, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Tune your feed',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.thumb_up_alt_outlined),
              title: const Text('More like this'),
              subtitle: Text('Show more from r/$sub and similar'),
              onTap: () {
                interest.bump(sub, 5);
                ref
                    .read(keywordStoreProvider.notifier)
                    .bumpTitle(widget.post.title, 2);
                Navigator.pop(ctx);
                toast("We'll show more like this");
              },
            ),
            ListTile(
              leading: const Icon(Icons.thumb_down_alt_outlined),
              title: const Text('Less like this'),
              subtitle: Text('Show less from r/$sub'),
              onTap: () {
                interest.bump(sub, -5);
                ref
                    .read(keywordStoreProvider.notifier)
                    .bumpTitle(widget.post.title, -2);
                Navigator.pop(ctx);
                toast("We'll show less like this");
              },
            ),
            ListTile(
              leading: Icon(muted
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded),
              title: Text(muted ? 'Unmute r/$sub' : 'Mute r/$sub in For You'),
              onTap: () {
                ref.read(mutedSubsProvider.notifier).toggle(sub);
                Navigator.pop(ctx);
                toast(muted
                    ? 'r/$sub unmuted'
                    : 'r/$sub muted from For You');
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _largeCard(BuildContext context) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(cs),
              const SizedBox(height: 10),
              Text(
                p.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
              ),
              if (p.linkFlairText != null) ...[
                const SizedBox(height: 8),
                _flair(cs, p.linkFlairText!),
              ],
              const SizedBox(height: 12),
              _media(cs),
              if (p.isSelf && p.selftext.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.selftext,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              _actions(cs),
            ],
          ),
        ),
      ),
    );
  }

  /// "Cards" — a full-width card like the default, but with media capped to a
  /// shorter banner height so cards stay compact and scannable.
  Widget _cardsCard(BuildContext context) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(cs),
              const SizedBox(height: 10),
              Text(
                p.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
              ),
              if (p.linkFlairText != null) ...[
                const SizedBox(height: 8),
                _flair(cs, p.linkFlairText!),
              ],
              const SizedBox(height: 12),
              _bannerMedia(cs, 180),
              if (p.isSelf && p.selftext.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.selftext,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              _actions(cs),
            ],
          ),
        ),
      ),
    );
  }

  /// "Mini cards" — compact: header + title with a small side thumbnail, full
  /// action row below.
  Widget _miniCard(BuildContext context) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    final thumb = _thumb(cs, 88);
    return Card(
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(cs),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700, height: 1.25),
                        ),
                        if (p.linkFlairText != null) ...[
                          const SizedBox(height: 6),
                          _flair(cs, p.linkFlairText!),
                        ],
                      ],
                    ),
                  ),
                  if (thumb != null) ...[
                    const SizedBox(width: 12),
                    thumb,
                  ],
                ],
              ),
              _actions(cs),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-width media constrained to [height] (cover-cropped). Falls back to the
  /// link preview / nothing for non-image posts.
  /// Feed preview URL, mid-resolution when the data-saver setting is on.
  String? _cardImg(Post p) =>
      ref.read(settingsControllerProvider).midResThumbnails
          ? (p.previewMedUrl ?? p.previewUrl)
          : p.previewUrl;

  Widget _bannerMedia(ColorScheme cs, double height) {
    final p = widget.post;
    if (p.type == PostType.self) return const SizedBox.shrink();
    if (p.type == PostType.link) return _linkPreview(cs);
    final blur = (p.over18 && ref.watch(settingsControllerProvider).blurNsfw) || p.spoiler;
    if (p.type == PostType.gallery && p.gallery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: NsfwBlur(
          blur: blur,
          child: GalleryCarousel(
              images: p.gallery, title: p.title, height: height),
        ),
      );
    }
    final url =
        _cardImg(p) ?? (p.gallery.isNotEmpty ? p.gallery.first.url : null);
    // Inline autoplay for videos (when enabled and not NSFW-blurred).
    if (p.type == PostType.video &&
        !blur &&
        ref.watch(settingsControllerProvider).autoplayMedia) {
      final vurl = p.hlsUrl ?? p.fallbackVideoUrl ?? resolveVideoUrl(p.url);
      if (vurl.isNotEmpty && !vurl.toLowerCase().endsWith('.gif')) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InlineVideo(
              key: ValueKey('iv_${p.id}'),
              url: vurl,
              poster: url,
              height: height,
              onTap: _openMedia,
            ),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: NsfwBlur(
        blur: blur,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onTap: _openMedia,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: cs.surfaceContainerHighest),
                      errorWidget: (_, __, ___) =>
                          Container(color: cs.surfaceContainerHighest),
                    )
                  else
                    Container(color: cs.surfaceContainerHighest),
                  if (p.type == PostType.video)
                    const Center(child: _PlayBadge()),
                  if (p.type == PostType.gallery)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Pill(
                          icon: Icons.collections_rounded,
                          label: '${p.gallery.length}'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Small square thumbnail for compact / mini layouts (null if no media).
  Widget? _thumb(ColorScheme cs, double size) {
    final p = widget.post;
    if (p.type == PostType.self) return null;
    final url =
        _cardImg(p) ?? (p.gallery.isNotEmpty ? p.gallery.first.url : p.thumbnailUrl);
    final blur = (p.over18 && ref.watch(settingsControllerProvider).blurNsfw) || p.spoiler;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && !blur)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: cs.surfaceContainerHighest),
                errorWidget: (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.link_rounded, color: cs.onSurfaceVariant),
                ),
              )
            else
              Container(
                color: cs.surfaceContainerHighest,
                child: Icon(
                    blur
                        ? Icons.visibility_off_rounded
                        : (p.type == PostType.link
                            ? Icons.link_rounded
                            : Icons.image_rounded),
                    color: cs.onSurfaceVariant),
              ),
            if (p.type == PostType.video)
              const Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 26),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    final p = widget.post;
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.push('/r/${p.subreddit}'),
          child: CircleAvatar(
            radius: 14,
            backgroundColor: cs.secondaryContainer,
            child: Text(
              p.subreddit.isNotEmpty ? p.subreddit[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondaryContainer),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/r/${p.subreddit}'),
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                children: [
                  TextSpan(
                    text: p.subredditPrefixed.isNotEmpty
                        ? p.subredditPrefixed
                        : 'r/${p.subreddit}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                  TextSpan(text: '  ·  u/${p.author}  ·  ${timeAgo(p.created)}'),
                ],
              ),
            ),
          ),
        ),
        if (p.stickied)
          Icon(Icons.push_pin_rounded, size: 16, color: cs.primary),
        if (p.over18)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(6)),
            child: Text('NSFW',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cs.onErrorContainer)),
          ),
      ],
    );
  }

  Widget _flair(ColorScheme cs, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      );

  Widget _media(ColorScheme cs) {
    final p = widget.post;
    final blur = (p.over18 && ref.watch(settingsControllerProvider).blurNsfw) || p.spoiler;
    switch (p.type) {
      case PostType.gallery:
        if (p.gallery.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: NsfwBlur(
              blur: blur,
              child: GalleryCarousel(images: p.gallery, title: p.title),
            ),
          );
        }
        return NsfwBlur(blur: blur, child: _mediaPreview(cs));
      case PostType.image:
      case PostType.gif:
      case PostType.video:
        return NsfwBlur(blur: blur, child: _mediaPreview(cs));
      case PostType.link:
        return _linkPreview(cs);
      case PostType.self:
        return const SizedBox.shrink();
    }
  }

  Widget _mediaPreview(ColorScheme cs) {
    final p = widget.post;
    final url = p.previewUrl ?? (p.gallery.isNotEmpty ? p.gallery.first.url : null);
    final aspect = (p.previewWidth != null &&
            p.previewHeight != null &&
            p.previewHeight! > 0)
        ? p.previewWidth! / p.previewHeight!
        : 16 / 9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: _openMedia,
          child: AspectRatio(
            aspectRatio: aspect.clamp(0.5, 2.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: cs.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.broken_image_outlined,
                          color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  Container(color: cs.surfaceContainerHighest),
                if (p.type == PostType.video)
                  const Center(child: _PlayBadge()),
                if (p.type == PostType.gallery)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _Pill(
                        icon: Icons.collections_rounded,
                        label: '${p.gallery.length}'),
                  ),
                if (p.type == PostType.gif)
                  const Positioned(
                      top: 8, left: 8, child: _Pill(label: 'GIF')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkPreview(ColorScheme cs) {
    final p = widget.post;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: _openMedia,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              if (p.thumbnailUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16)),
                  child: CachedNetworkImage(
                    imageUrl: p.thumbnailUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const SizedBox(width: 72, height: 72),
                  ),
                )
              else
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  child: Icon(Icons.link_rounded, color: cs.onSurfaceVariant),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(p.domain,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.open_in_new_rounded,
                    size: 18, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(ColorScheme cs) {
    // Live values from the shared overrides store (kept in sync with the detail).
    final ov = ref.watch(
        postOverridesProvider.select((m) => m[widget.post.id]));
    final likes = ov != null ? ov.likes : widget.post.likes;
    final score = ov?.score ?? widget.post.score;
    final saved = ov?.saved ?? widget.post.saved;
    final numComments = ov?.numComments ?? widget.post.numComments;
    return Row(
      children: [
        _VotePill(
          score: score,
          likes: likes,
          onUp: () => _vote(1),
          onDown: () => _vote(-1),
        ),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.mode_comment_outlined,
          label: compactNumber(numComments),
          onTap: _openDetail,
        ),
        const Spacer(),
        _ReadToggle(post: widget.post),
        IconButton(
          onPressed: _toggleSave,
          icon: Icon(saved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded),
          color: saved ? cs.primary : null,
        ),
        IconButton(
          onPressed: () => showPostActionsSheet(context, ref, widget.post),
          icon: const Icon(Icons.more_vert_rounded),
        ),
      ],
    );
  }
}

/// "Read" toggle shown on every post card (left of Save). Marks the post as
/// read/unread in local history; read posts get a filled, accent check.
class _ReadToggle extends ConsumerWidget {
  const _ReadToggle({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final seen = ref.watch(historyContainsProvider(post.id));
    return IconButton(
      tooltip: seen ? 'Mark as unread' : 'Mark as read',
      onPressed: () {
        final h = ref.read(historyControllerProvider.notifier);
        seen ? h.removeViewed(post.id) : h.markViewed(post);
      },
      icon: Icon(
        seen ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
        color: seen ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }
}

class _VotePill extends StatelessWidget {
  const _VotePill({
    required this.score,
    required this.likes,
    required this.onUp,
    required this.onDown,
  });
  final int score;
  final bool? likes;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final votes = Theme.of(context).extension<VoteColors>()!;
    final up = likes == true;
    final down = likes == false;
    final countColor = up ? votes.up : (down ? votes.down : cs.onSurfaceVariant);
    // Bloom "split" votes: a soft pill holding up / count / down.
    return Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _miniBtn(Icons.arrow_upward_rounded, up ? votes.up : cs.onSurfaceVariant, onUp),
          Text(compactNumber(score),
              style: TextStyle(fontWeight: FontWeight.w700, color: countColor)),
          _miniBtn(Icons.arrow_downward_rounded,
              down ? votes.down : cs.onSurfaceVariant, onDown),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData icon, Color fg, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        icon: Icon(icon, color: fg),
      );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.black54, shape: BoxShape.circle),
        child: const Icon(Icons.play_arrow_rounded,
            color: Colors.white, size: 36),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({this.icon, required this.label});
  final IconData? icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
