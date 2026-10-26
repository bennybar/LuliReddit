import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/analytics.dart';
import '../../core/format.dart';
import '../../core/open_link.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/image_decode.dart';
import 'expiring_ids.dart';
import 'content_filters.dart';
import 'inline_video.dart';
import 'post_overrides.dart';
import '../../core/theme/app_theme.dart';
import '../../models/post.dart';
import '../history/history_store.dart';
import '../media/gallery_carousel.dart';
import '../media/media_viewers.dart';
import '../media/nsfw_blur.dart';
import '../media/share_media.dart';
import '../post/compose_sheet.dart';
import '../foryou/for_you_learner.dart';
import '../foryou/tune_sheet.dart';
import '../post/post_actions.dart';
import '../settings/settings_controller.dart';
import '../web/reddit_web_screen.dart';
import 'swipe_actions.dart';

/// Feed preview URL, mid-resolution when the data-saver setting is on.
String? _cardImg(Post p, Settings s) {
  final preview =
      s.midResThumbnails ? (p.previewMedUrl ?? p.previewUrl) : p.previewUrl;
  if (preview != null) return preview;
  // Direct image links (preview.redd.it / i.redd.it / i.imgur.com) carry no
  // preview block — use the URL itself.
  if (p.type == PostType.image || p.type == PostType.gif) return p.url;
  return null;
}

/// The image URL a full-width card shows (shared with the list's prefetcher).
String? feedImageUrl(Post p, Settings s) =>
    _cardImg(p, s) ?? (p.gallery.isNotEmpty ? p.gallery.first.url : null);

bool _blurOf(Post p, Settings s) => (p.over18 && s.blurNsfw) || p.spoiler;
String _blurLabel(Post p, Settings s) =>
    p.over18 && s.blurNsfw ? 'NSFW' : 'Spoiler';

void _undoSnack(BuildContext context, String msg, VoidCallback undo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    content: Text(msg),
    action: SnackBarAction(label: 'Undo', onPressed: undo),
  ));
}

/// Removes [post] from Home / For You for a day (local only), with Undo.
void dismissPost(BuildContext context, WidgetRef ref, Post post) {
  final dismissed = ref.read(dismissedPostsProvider.notifier);
  final learner = ref.read(forYouLearnerProvider);
  dismissed.add(post.id);
  learner.dismiss(post);
  _undoSnack(context, 'Dismissed for today', () {
    dismissed.remove(post.id);
    learner.dismiss(post, undo: true);
  });
}

/// Hides [post]'s subreddit from the front page for 7 days (local only), with
/// Undo.
void hideSubFromHome(BuildContext context, WidgetRef ref, Post post) {
  final sub = post.subreddit.toLowerCase();
  if (sub.isEmpty) return;
  final hidden = ref.read(hiddenHomeSubsProvider.notifier);
  final learner = ref.read(forYouLearnerProvider);
  hidden.add(sub);
  learner.hideSubreddit(post);
  _undoSnack(
      context, 'r/${post.subreddit} hidden from your front page for 7 days',
      () {
    hidden.remove(sub);
    learner.hideSubreddit(post, undo: true);
  });
}

/// Adds [post]'s subreddit to the content filters: hidden from every feed but
/// its own, for good, with Undo.
void filterOutSub(BuildContext context, WidgetRef ref, Post post) {
  final sub = post.subreddit.toLowerCase();
  if (sub.isEmpty) return;
  final filters = ref.read(contentFiltersProvider.notifier);
  final learner = ref.read(forYouLearnerProvider);
  filters.add('subreddit', sub);
  learner.filterOutSubreddit(post);
  _undoSnack(context, 'r/${post.subreddit} filtered out of your feeds', () {
    filters.remove('subreddit', sub);
    learner.filterOutSubreddit(post, undo: true);
  });
}

/// "tomorrow at 09:00" for a post you asked to be reminded about, or null.
// TODO(reminders): the reminders area replaces this with the pending
// reminders store; until then no post has one.
final pendingReminderLabelProvider =
    Provider.family<String?, String>((ref, postId) => null);

/// A post in a feed, in the layout chosen in Settings (Default / Cards / Mini
/// cards / Calm / Calm cards). [dismissible]: Home / For You, where the
/// "Dismiss" swipe applies; [frontpage]: Home, For You, Best / Hot / New,
/// where "Hide subreddit for 7 days" applies. [swipeOverride] replaces the
/// swipe actions (start, end), e.g. Saved, where both sides unsave.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.dismissible = false,
    this.frontpage = false,
    this.swipeOverride,
  });
  final Post post;
  final bool dismissible;
  final bool frontpage;
  final (SwipeSpec?, SwipeSpec?)? swipeOverride;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  // Tapping the "u/author" part of the header opens their profile.
  late final TapGestureRecognizer _authorTap = TapGestureRecognizer()
    ..onTap = _openAuthor;

  // Counts the For You impression once the card has stayed mostly on screen
  // for a moment.
  Timer? _impressionTimer;

  // A read post with Settings → Dim read posts → Text only: its title and
  // text fade (images stay bright). Set in build.
  bool _dimText = false;

  @override
  void dispose() {
    _authorTap.dispose();
    _impressionTimer?.cancel();
    super.dispose();
  }

  // A card flung past mid-scroll wasn't really seen; counting it would bury
  // posts the user never had a chance to read. Only a card that sits ≥60%
  // visible for a second counts as shown.
  void _onVisibility(VisibilityInfo info) {
    _impressionTimer?.cancel();
    if (info.visibleFraction < 0.6) return;
    _impressionTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (widget.post.feedReason != null) {
        ref.read(forYouLearnerProvider).impression(widget.post);
      }
      // "Mark read on scroll": a card actually seen counts as read (history
      // only — no interest learning, which is for real engagement).
      final s = ref.read(settingsControllerProvider);
      if (s.markReadOnScroll && s.trackHistory) {
        ref.read(historyControllerProvider.notifier).markViewed(widget.post);
      }
    });
  }

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
    final learner = ref.read(forYouLearnerProvider)
      ..vote(widget.post, current, target);
    try {
      await ref.read(redditRepositoryProvider).vote(widget.post.fullname, target);
    } catch (e) {
      overrides.setVote(widget.post, current); // revert
      learner.vote(widget.post, target, current);
      if (mounted) showActionError(context, 'vote', e);
    }
  }

  Future<void> _toggleSave() async {
    final overrides = ref.read(postOverridesProvider.notifier);
    final next = !_ov.saved;
    overrides.setSaved(widget.post, next);
    final learner = ref.read(forYouLearnerProvider)..save(widget.post, next);
    // TODO(reminders): Kotlin offers a reminder on save (PostReminders.offer)
    // and cancels it on unsave.
    try {
      await ref.read(redditRepositoryProvider).setSaved(widget.post.fullname, next);
    } catch (e) {
      overrides.setSaved(widget.post, !next);
      learner.save(widget.post, !next);
      if (mounted) showActionError(context, next ? 'save' : 'unsave', e);
    }
  }

  void _openDetail() {
    Analytics.track('post_opened');
    if (ref.read(settingsControllerProvider).trackHistory) {
      ref.read(historyControllerProvider.notifier).markViewed(widget.post);
    }
    ref.read(forYouLearnerProvider).open(widget.post);
    context.push(
      '/comments/${widget.post.subreddit}/${widget.post.id}',
      extra: widget.post,
    );
  }

  void _openMedia() {
    final p = widget.post;
    // Viewing media is engagement too (slightly stronger than a plain open).
    if (p.type != PostType.self) ref.read(forYouLearnerProvider).viewMedia(p);
    switch (p.type) {
      case PostType.image:
        openImageViewer(context, p.previewUrl ?? p.url, title: p.title);
      case PostType.gif:
        // Play reddit's mp4 variant (small, loops); else the animated .gif.
        if (p.gifMp4Url != null) {
          openVideoViewer(context, p.gifMp4Url!,
              title: p.title, downloadUrl: p.gifMp4Url, externalUrl: p.url);
        } else {
          openImageViewer(context, p.url, title: p.title);
        }
      case PostType.gallery:
        openGalleryViewer(context, p.gallery, title: p.title);
      case PostType.video:
        // External videos (YouTube…) open in their own app.
        openPostVideo(context, p);
      case PostType.link:
        openInBrowser(context, Uri.parse(p.url));
      case PostType.self:
        _openDetail();
    }
  }

  void _openSubreddit() => context.push('/r/${widget.post.subreddit}');

  void _openAuthor() {
    final a = widget.post.author;
    if (a.isNotEmpty && a != '[deleted]') context.push('/u/$a');
  }

  void _more() => showPostActionsSheet(context, ref, widget.post);

  void _share() {
    // Sharing is a strong interest signal (as in the ⋮ sheet).
    ref.read(forYouLearnerProvider).share(widget.post);
    shareUrl(context, 'https://reddit.com${widget.post.permalink}',
        subject: widget.post.title);
  }

  /// The image(s) / video themselves, downloaded, rather than a link.
  void _shareMedia() {
    ref.read(forYouLearnerProvider).share(widget.post);
    shareAsMedia(context, widget.post);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final seen = ref.watch(historyContainsProvider(widget.post.id));
    // Settings → Dim read posts: the whole card (veil), or only its title and
    // text so images and videos stay bright.
    final dimRead = seen && settings.trackHistory;
    _dimText = dimRead && settings.dimReadTextOnly;
    Widget card = switch (settings.postDisplay) {
      PostDisplay.large => _largeCard(context, settings),
      PostDisplay.card => _cardsCard(context, settings),
      PostDisplay.mini => _miniCard(context, settings),
      PostDisplay.calm => _calmCard(context, settings),
      PostDisplay.calmCards => _calmCardsCard(context, settings),
    };
    // Dim already-viewed posts when history tracking is on.
    if (dimRead && !settings.dimReadTextOnly) {
      // A page-colour veil looks the same as Opacity(0.55) — the card sits on
      // the page surface — but Opacity re-renders the whole card, images and
      // all, into an offscreen layer on every frame it scrolls.
      card = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.45)),
        child: card,
      );
    }
    // "Why you're seeing this" banner (For You feed only). Calm shows the
    // reason in the card header instead.
    final reason = widget.post.feedReason;
    if (reason != null && !settings.postDisplay.isCalm) {
      card = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_reasonRow(context, reason), card],
      );
    }
    // For You impressions (shown-but-never-opened posts get demoted on the
    // next build) and "mark read on scroll" both need to know what was seen.
    if (reason != null || settings.markReadOnScroll) {
      card = VisibilityDetector(
        key: Key('impression_${widget.post.id}'),
        onVisibilityChanged: _onVisibility,
        child: card,
      );
    }
    // The whole card, "why" banner included, is the swipe target.
    return GestureDetector(
      onLongPress: _showTuneSheet,
      child: SwipeActions(
        enabled: settings.swipeActions,
        start: widget.swipeOverride?.$1 ?? _swipe(settings.swipePostStart),
        end: widget.swipeOverride?.$2 ?? _swipe(settings.swipePostEnd),
        child: card,
      ),
    );
  }

  Widget _reasonRow(BuildContext context, String reason) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 8, 0),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: cs.primary),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
    );
  }

  /// What a swipe on this card does, per Settings → Swipe actions.
  SwipeSpec? _swipe(SwipeAction action) {
    final votes = Theme.of(context).extension<VoteColors>()!;
    final cs = Theme.of(context).colorScheme;
    final p = widget.post;
    return switch (action) {
      SwipeAction.upvote => SwipeSpec(action.icon, votes.up, () => _vote(1)),
      SwipeAction.downvote =>
        SwipeSpec(action.icon, votes.down, () => _vote(-1)),
      SwipeAction.save => SwipeSpec(action.icon, cs.primary, _toggleSave),
      SwipeAction.reply => SwipeSpec(action.icon, cs.tertiary, () async {
          final reply = await showReplySheet(context, ref,
              parentFullname: p.fullname, parentDepth: -1, post: p);
          if (reply != null) {
            ref.read(postOverridesProvider.notifier).bumpComments(p, 1);
          }
        }),
      SwipeAction.hide =>
        SwipeSpec(action.icon, cs.error, () => hidePost(context, ref, p)),
      // Only Home / For You can dismiss; elsewhere this side does nothing.
      SwipeAction.dismiss => widget.dismissible
          ? SwipeSpec(
              action.icon, cs.secondary, () => dismissPost(context, ref, p))
          : null,
      SwipeAction.hideSub => widget.frontpage
          ? SwipeSpec(action.icon, cs.tertiary,
              () => hideSubFromHome(context, ref, p))
          : null,
      SwipeAction.collapse || SwipeAction.none => null,
    };
  }

  /// Long-press → "Tune For You": why it's here, and explicit More/Less.
  void _showTuneSheet() => showTuneSheet(context, ref, widget.post);

  /// Fades a read post's title / text when only text is dimmed.
  Widget _readDim(Widget child) =>
      _dimText ? Opacity(opacity: 0.5, child: child) : child;

  /// A Bloom card: filled, radius 28 unless [shape] is given; the whole card
  /// is the ink target.
  Widget _bloomCard(Widget child, {BorderRadius? radius, Color? color}) {
    final shape = RoundedRectangleBorder(
        borderRadius: radius ?? BorderRadius.circular(28));
    return Card(
      color: color,
      shape: shape,
      // The ink is clipped to the shape; the card itself isn't (a clip per
      // card costs while scrolling).
      child: InkWell(onTap: _openDetail, customBorder: shape, child: child),
    );
  }

  Widget _title(BuildContext context, {int? maxLines, bool small = false}) {
    final t = Theme.of(context).textTheme;
    return _readDim(Text(
      widget.post.title,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: (small ? t.titleSmall : t.titleMedium)
          ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
    ));
  }

  Widget _snippet(BuildContext context, int maxLines) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _readDim(Text(
          widget.post.snippet,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        )),
      );

  Widget _largeCard(BuildContext context, Settings s) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return _bloomCard(Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(cs, s),
          const SizedBox(height: 10),
          _title(context),
          if (p.linkFlairText != null) ...[
            const SizedBox(height: 8),
            _flair(cs, p.linkFlairText!),
          ],
          CrosspostLine(post: p),
          ReminderLine(post: p),
          const SizedBox(height: 12),
          _media(cs, s),
          PollOptions(post: p),
          if (p.snippet.isNotEmpty) _snippet(context, 3),
          _actions(cs),
        ],
      ),
    ));
  }

  /// "Cards" — a full-width card like the default, but with media capped to a
  /// shorter banner height so cards stay compact and scannable.
  Widget _cardsCard(BuildContext context, Settings s) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return _bloomCard(Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(cs, s),
          const SizedBox(height: 10),
          _title(context),
          if (p.linkFlairText != null) ...[
            const SizedBox(height: 8),
            _flair(cs, p.linkFlairText!),
          ],
          CrosspostLine(post: p),
          ReminderLine(post: p),
          const SizedBox(height: 12),
          _bannerMedia(cs, s, 180),
          PollOptions(post: p),
          if (p.snippet.isNotEmpty) _snippet(context, 2),
          _actions(cs),
        ],
      ),
    ));
  }

  /// "Mini cards" — compact: header + title with a small side thumbnail, full
  /// action row below.
  Widget _miniCard(BuildContext context, Settings s) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    final thumb = _thumb(cs, s, 88);
    return _bloomCard(Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(cs, s),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(context, maxLines: 3, small: true),
                    if (p.linkFlairText != null) ...[
                      const SizedBox(height: 6),
                      _flair(cs, p.linkFlairText!),
                    ],
                    CrosspostLine(post: p),
                    ReminderLine(post: p),
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
    ));
  }

  /// A cover-cropped feed image decoded at screen width (the prefetcher uses
  /// the same size).
  Widget _feedImage(ColorScheme cs, String url, {bool brokenIcon = false}) =>
      CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: feedDecodeWidth(context),
        placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
        errorWidget: (_, __, ___) => Container(
          color: cs.surfaceContainerHighest,
          child: brokenIcon
              ? Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant)
              : null,
        ),
      );

  /// The overlays on a media preview: play badge, external-video / GIF /
  /// gallery pills.
  List<Widget> _mediaBadges({bool gifTopStart = false, bool gifIcon = true}) {
    final p = widget.post;
    return [
      if (p.type == PostType.video ||
          (p.type == PostType.gif && !gifTopStart))
        const Center(child: _PlayBadge()),
      // "YouTube ↗" on a video that opens outside Ilay, so the tap's result
      // isn't a surprise.
      if (p.type == PostType.video && isExternalVideo(p))
        Positioned(
          top: 8,
          right: 8,
          child: _Pill(
              icon: Icons.open_in_new_rounded,
              label: externalVideoSource(p)),
        ),
      if (p.type == PostType.gif)
        Positioned(
          top: 8,
          left: gifTopStart ? 8 : null,
          right: gifTopStart ? null : 8,
          child: _Pill(icon: gifIcon ? Icons.gif_rounded : null, label: 'GIF'),
        ),
      if (p.type == PostType.gallery)
        Positioned(
          top: 8,
          right: 8,
          child: _Pill(
              icon: Icons.collections_rounded, label: '${p.gallery.length}'),
        ),
    ];
  }

  /// The inline autoplaying video for a video post, or null when it isn't
  /// one (or autoplay is off / it's blurred / it plays outside Ilay).
  Widget? _inlineVideo(Settings s, double height, String? poster) {
    final p = widget.post;
    if (p.type != PostType.video ||
        _blurOf(p, s) ||
        !s.autoplayMedia ||
        isExternalVideo(p)) {
      return null;
    }
    final vurl = postVideoUrl(p);
    if (vurl.isEmpty || vurl.toLowerCase().endsWith('.gif')) return null;
    return InlineVideo(
      key: ValueKey('iv_${p.id}'),
      url: vurl,
      poster: poster,
      height: height,
      onTap: _openMedia,
      startMuted: !s.autoplaySound,
    );
  }

  /// A gallery in a feed card: the Material 3 carousel (2+ images, Settings ›
  /// Gallery carousel in feeds), else one image at a time. [height]: the
  /// card's media height; the carousel keeps it between 220 and 340.
  Widget _feedGallery(Settings s, {double? height, BorderRadius? clip}) {
    final p = widget.post;
    if (s.feedGalleryCarousel && p.gallery.length > 1) {
      return GalleryM3Carousel(
          images: p.gallery,
          title: p.title,
          height: (height ?? 300).clamp(220.0, 340.0));
    }
    final g =
        GalleryCarousel(images: p.gallery, title: p.title, height: height);
    return clip == null ? g : ClipRRect(borderRadius: clip, child: g);
  }

  /// Full-width media for the "Cards" layout, cover-cropped to [height].
  Widget _bannerMedia(ColorScheme cs, Settings s, double height) {
    final p = widget.post;
    if (p.type == PostType.self) return const SizedBox.shrink();
    if (p.type == PostType.link) return _linkPreview(cs);
    final blur = _blurOf(p, s);
    if (p.type == PostType.gallery && p.gallery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: NsfwBlur(
          blur: blur,
          label: _blurLabel(p, s),
          child: _feedGallery(s, height: height),
        ),
      );
    }
    final url = feedImageUrl(p, s);
    // Inline autoplay for videos (when enabled and not NSFW-blurred).
    final video = _inlineVideo(s, height, url);
    if (video != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ClipRRect(borderRadius: BorderRadius.circular(16), child: video),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: NsfwBlur(
        blur: blur,
        blurredImageUrl: p.blurredPreviewUrl,
        label: _blurLabel(p, s),
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
                    _feedImage(cs, url)
                  else
                    Container(color: cs.surfaceContainerHighest),
                  ..._mediaBadges(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Small square thumbnail for the mini layout (null if no media).
  Widget? _thumb(ColorScheme cs, Settings s, double size) {
    final p = widget.post;
    if (p.type == PostType.self) return null;
    final url = _cardImg(p, s) ??
        (p.gallery.isNotEmpty ? p.gallery.first.url : p.thumbnailUrl);
    final blur = _blurOf(p, s);
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
                // Cover-cropped into a square: 2× leaves room for a 2:1 image.
                memCacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context) * 2).round(),
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

  Widget _header(ColorScheme cs, Settings s) {
    final p = widget.post;
    return Row(
      children: [
        GestureDetector(
          onTap: _openSubreddit,
          child: LetterAvatar(
            name: p.subreddit,
            imageUrl: s.subredditIcons ? p.subredditIcon : null,
            size: 28,
            container: cs.secondaryContainer,
            content: cs.onSecondaryContainer,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _openSubreddit,
            child: Text.rich(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              TextSpan(
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                children: [
                  TextSpan(
                    text: p.subredditPrefixed.isNotEmpty
                        ? p.subredditPrefixed
                        : 'r/${p.subreddit}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: 'u/${p.author}',
                    recognizer: _authorTap,
                  ),
                  TextSpan(text: '  ·  ${timeAgo(p.created)}'),
                ],
              ),
            ),
          ),
        ),
        if (p.stickied)
          Icon(Icons.push_pin_rounded, size: 16, color: cs.primary),
        if (p.over18) const _NsfwTag(),
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

  /// Default layout media: gallery carousel, aspect-correct preview, or link
  /// card.
  Widget _media(ColorScheme cs, Settings s) {
    final p = widget.post;
    final blur = _blurOf(p, s);
    switch (p.type) {
      case PostType.gallery:
        if (p.gallery.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: NsfwBlur(
              blur: blur,
              label: _blurLabel(p, s),
              child: _feedGallery(s),
            ),
          );
        }
        return NsfwBlur(
            blur: blur,
            blurredImageUrl: p.blurredPreviewUrl,
            label: _blurLabel(p, s),
            child: _mediaPreview(cs, s));
      case PostType.image:
      case PostType.gif:
      case PostType.video:
        return NsfwBlur(
            blur: blur,
            blurredImageUrl: p.blurredPreviewUrl,
            label: _blurLabel(p, s),
            child: _mediaPreview(cs, s));
      case PostType.link:
        return _linkPreview(cs);
      case PostType.self:
        return const SizedBox.shrink();
    }
  }

  Widget _mediaPreview(ColorScheme cs, Settings s) {
    final p = widget.post;
    // Mid-res when the data-saver setting is on, like the other layouts.
    final preview =
        s.midResThumbnails ? (p.previewMedUrl ?? p.previewUrl) : p.previewUrl;
    final url = preview ?? (p.gallery.isNotEmpty ? p.gallery.first.url : null);
    final aspect = ((p.previewWidth != null &&
                p.previewHeight != null &&
                p.previewHeight! > 0)
            ? p.previewWidth! / p.previewHeight!
            : 16 / 9)
        .clamp(0.5, 2.0);
    // Inline autoplay for videos (when enabled and not NSFW-blurred), as in
    // the Cards and Calm layouts.
    if (p.type == PostType.video &&
        !_blurOf(p, s) &&
        s.autoplayMedia &&
        !isExternalVideo(p)) {
      return LayoutBuilder(builder: (context, c) {
        final video = _inlineVideo(s, c.maxWidth / aspect, url);
        if (video == null) return _previewBox(cs, url, aspect);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child:
              ClipRRect(borderRadius: BorderRadius.circular(16), child: video),
        );
      });
    }
    return _previewBox(cs, url, aspect);
  }

  Widget _previewBox(ColorScheme cs, String? url, double aspect) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onTap: _openMedia,
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    _feedImage(cs, url, brokenIcon: true)
                  else
                    Container(color: cs.surfaceContainerHighest),
                  ..._mediaBadges(gifTopStart: true, gifIcon: false),
                ],
              ),
            ),
          ),
        ),
      );

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
                    memCacheWidth:
                        (72 * MediaQuery.devicePixelRatioOf(context) * 2)
                            .round(),
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

  /// Live vote / save / comment state (optimistic overrides first).
  ({bool? likes, int score, bool saved, int numComments}) _live() {
    final ov = ref.watch(
        postOverridesProvider.select((m) => m[widget.post.id]));
    final p = widget.post;
    return (
      likes: ov != null ? ov.likes : p.likes,
      score: ov?.score ?? p.score,
      saved: ov?.saved ?? p.saved,
      numComments: ov?.numComments ?? p.numComments,
    );
  }

  Widget _actions(ColorScheme cs) {
    // Live values from the shared overrides store (kept in sync with the detail).
    final live = _live();
    return Row(
      children: [
        _VotePill(
          score: live.score,
          likes: live.likes,
          onUp: () => _vote(1),
          onDown: () => _vote(-1),
        ),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.mode_comment_outlined,
          label: compactNumber(live.numComments),
          onTap: _openDetail,
        ),
        const Spacer(),
        _ReadToggle(post: widget.post),
        IconButton(
          onPressed: _toggleSave,
          tooltip: live.saved ? 'Unsave' : 'Save',
          icon: Icon(live.saved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded),
          color: live.saved ? cs.primary : cs.onSurfaceVariant,
        ),
        IconButton(
          onPressed: _more,
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          color: cs.onSurfaceVariant,
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Calm layout
  // -------------------------------------------------------------------------

  /// "Calm" — one card per post: a rounded-square avatar header, a bold
  /// title, a flair pill, media at its full aspect ratio (not cropped) and a
  /// connected [↑ score][↓][comments] group. Mark-read lives in the ⋮ sheet.
  Widget _calmCard(BuildContext context, Settings s) {
    return _bloomCard(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _calmBody(context, s,
                  mediaRadius: BorderRadius.circular(_calmMediaRadius)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  _calmActionGroup(context, withComments: true),
                  const Spacer(),
                  ..._calmShareSave(context),
                ],
              ),
            ),
          ],
        ),
      ),
      radius: BorderRadius.circular(_calmOuter),
      color: calmCardColor(context),
    );
  }

  /// "Calm cards" — each post its own connected group: the content, the media
  /// (edge to edge) and the actions as separate segments, 3 apart.
  Widget _calmCardsCard(BuildContext context, Settings s) {
    final p = widget.post;
    final color = calmCardColor(context);
    const outer = Radius.circular(_calmOuter);
    const inner = Radius.circular(_calmInner);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloomCard(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: _calmBody(context, s),
            ),
            radius: const BorderRadius.only(
                topLeft: outer,
                topRight: outer,
                bottomLeft: inner,
                bottomRight: inner),
            color: color,
          ),
          if (p.type != PostType.self) ...[
            const SizedBox(height: _calmGap),
            _calmMedia(context, s, BorderRadius.circular(_calmInner),
                topPad: 0),
          ],
          const SizedBox(height: _calmGap),
          _bloomCard(
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  _calmActionGroup(context, withComments: false),
                  const SizedBox(width: 8),
                  CalmButtonGroup(buttons: [
                    CalmButton(
                        icon: Icons.mode_comment_outlined,
                        label: compactNumber(_live().numComments),
                        onTap: _openDetail),
                  ]),
                  const Spacer(),
                  ..._calmShareSave(context),
                ],
              ),
            ),
            radius: const BorderRadius.only(
                topLeft: inner,
                topRight: inner,
                bottomLeft: outer,
                bottomRight: outer),
            color: color,
          ),
        ],
      ),
    );
  }

  /// Header, title, flair, crosspost, media (when [mediaRadius] is set), poll
  /// and selftext.
  Widget _calmBody(BuildContext context, Settings s,
      {BorderRadius? mediaRadius}) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _calmHeader(context, s),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _readDim(Text(
            p.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: -0.1,
              color: cs.onSurface,
            ),
          )),
        ),
        if (p.linkFlairText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CalmFlair(raw: p.linkFlairText!),
          ),
        CrosspostLine(post: p),
        ReminderLine(post: p),
        if (mediaRadius != null) _calmMedia(context, s, mediaRadius),
        if (p.pollOptions.isNotEmpty) ...[
          const SizedBox(height: 10),
          PollOptions(post: p),
        ],
        if (p.snippet.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _readDim(Text(
              p.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            )),
          ),
      ],
    );
  }

  Widget _calmHeader(BuildContext context, Settings s) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    // The subreddit is already the line above: drop a trailing " · r/sub"
    // from the reason.
    String? reason = p.feedReason;
    for (final suffix in [
      ' · r/${p.subreddit}',
      ' · ${p.subredditPrefixed}'
    ]) {
      if (reason != null && reason.endsWith(suffix)) {
        reason = reason.substring(0, reason.length - suffix.length);
      }
    }
    // Expressive: a rounded-square avatar in one of three tonal pairs, picked
    // per subreddit so a sub keeps its colour.
    final (bg, fg) = switch (_javaHash(p.subreddit.toLowerCase()) % 3) {
      0 => (cs.primaryContainer, cs.onPrimaryContainer),
      1 => (cs.secondaryContainer, cs.onSecondaryContainer),
      _ => (cs.tertiaryContainer, cs.onTertiaryContainer),
    };
    final age = timeAgo(p.created);
    return Row(
      children: [
        GestureDetector(
          onTap: _openSubreddit,
          child: LetterAvatar(
            name: p.subreddit,
            imageUrl: s.subredditIcons ? p.subredditIcon : null,
            size: 36,
            container: bg,
            content: fg,
            radius: 12,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _openSubreddit,
                child: Text(
                  p.subredditPrefixed.isNotEmpty
                      ? p.subredditPrefixed
                      : 'r/${p.subreddit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                ),
              ),
              if (reason != null)
                // For You: why it's here, in place of the author, then the
                // post's age (kept visible when the reason is long). Tap →
                // the "why you're seeing this" / tune sheet.
                GestureDetector(
                  onTap: _showTuneSheet,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 13, color: cs.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.primary),
                        ),
                      ),
                      Text(' · $age',
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: _openAuthor,
                  child: Text(
                    'u/${p.author} · $age',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        if (p.stickied)
          Icon(Icons.push_pin_rounded, size: 16, color: cs.primary),
        if (p.over18) const _NsfwTag(),
        SizedBox(
          width: 36,
          height: 36,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _more,
            child: Icon(Icons.more_vert_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
                semanticLabel: 'More'),
          ),
        ),
      ],
    );
  }

  /// Calm media in [radius]: the preview's own aspect ratio (clamped 1:2 …
  /// 2:1; 16:10 when unknown) — galleries, inline video, or a link block.
  Widget _calmMedia(BuildContext context, Settings s, BorderRadius radius,
      {double topPad = 10}) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    if (p.type == PostType.self) return const SizedBox.shrink();
    final blur = _blurOf(p, s);
    if (p.type == PostType.link) {
      final img = _cardImg(p, s) ?? p.thumbnailUrl;
      return Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Material(
          color: _calmControlColor(context),
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openMedia,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (img != null)
                  NsfwBlur(
                    blur: blur,
                    blurredImageUrl: p.blurredPreviewUrl,
                    label: _blurLabel(p, s),
                    child: AspectRatio(
                        aspectRatio: 2, child: _feedImage(cs, img)),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(p.domain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                      Icon(Icons.open_in_new_rounded,
                          size: 14, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: LayoutBuilder(builder: (context, c) {
        // The media's own shape, like the Default layout (galleries often
        // have no preview size: use the first image's).
        final first = p.gallery.isNotEmpty ? p.gallery.first : null;
        final w = p.previewWidth ?? first?.width;
        final h = p.previewHeight ?? first?.height;
        final aspect = w != null && h != null && h > 0
            ? (w / h).clamp(0.5, 2.0)
            : 16 / 10;
        final height = c.maxWidth / aspect;
        if (p.type == PostType.gallery && p.gallery.isNotEmpty) {
          return NsfwBlur(
            blur: blur,
            label: _blurLabel(p, s),
            child: _feedGallery(s, height: height, clip: radius),
          );
        }
        final url = feedImageUrl(p, s);
        // Inline autoplay for videos (when enabled and not NSFW-blurred).
        final video = _inlineVideo(s, height, url);
        if (video != null) {
          return ClipRRect(borderRadius: radius, child: video);
        }
        return NsfwBlur(
          blur: blur,
          blurredImageUrl: p.blurredPreviewUrl,
          label: _blurLabel(p, s),
          child: ClipRRect(
            borderRadius: radius,
            child: GestureDetector(
              onTap: _openMedia,
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null)
                      _feedImage(cs, url, brokenIcon: true)
                    else
                      Container(color: cs.surfaceContainerHighest),
                    ..._mediaBadges(),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// [↑ score][↓] (+ [comments] when [withComments]) as one connected button
  /// group.
  Widget _calmActionGroup(BuildContext context, {required bool withComments}) {
    final votes = Theme.of(context).extension<VoteColors>()!;
    final live = _live();
    final up = live.likes == true;
    final down = live.likes == false;
    return CalmButtonGroup(buttons: [
      CalmButton(
        icon: Icons.arrow_upward_rounded,
        label: compactNumber(live.score),
        semanticLabel: 'Upvote',
        toggled: up,
        tint: up ? votes.up : null,
        labelTint: down ? votes.down : null,
        onTap: () => _vote(1),
      ),
      CalmButton(
        icon: Icons.arrow_downward_rounded,
        semanticLabel: 'Downvote',
        toggled: down,
        tint: down ? votes.down : null,
        onTap: () => _vote(-1),
      ),
      if (withComments)
        CalmButton(
            icon: Icons.mode_comment_outlined,
            label: compactNumber(live.numComments),
            onTap: _openDetail),
    ]);
  }

  List<Widget> _calmShareSave(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.post;
    final saved = _live().saved;
    return [
      if (canShareAsMedia(p))
        CalmGhost(
          icon: p.type == PostType.video || p.type == PostType.gif
              ? Icons.movie_outlined
              : Icons.image_outlined,
          label: 'Share as media',
          color: cs.onSurfaceVariant,
          onTap: _shareMedia,
        ),
      CalmGhost(
          icon: Icons.share_rounded,
          label: 'Share',
          color: cs.onSurfaceVariant,
          onTap: _share),
      CalmGhost(
        icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        label: saved ? 'Unsave' : 'Save',
        color: saved ? cs.primary : cs.onSurfaceVariant,
        onTap: _toggleSave,
      ),
    ];
  }
}

/// Outer corner of a Calm card; a Calm cards post's segments meet at
/// [_calmInner], [_calmGap] apart.
const double _calmOuter = 28;
const double _calmInner = 6;
const double _calmGap = 3;

/// Calm media and link cards: evenly rounded.
const double _calmMediaRadius = 24;

bool _isLight(ColorScheme cs) => cs.surface.computeLuminance() > 0.5;

/// Calm's surfaces. In light mode surfaceContainerLow is almost the page
/// colour, so cards were lost in one off-white sheet: cards use a clearly
/// tinted container. Dark mode already contrasts.
Color calmCardColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return _isLight(cs) ? cs.surfaceContainerHigh : cs.surfaceContainerLow;
}

/// Controls inside a Calm card go a lighter tint (light mode) to stand out
/// from the card.
Color _calmControlColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return _isLight(cs) ? cs.surfaceContainerLow : cs.surfaceContainerHigh;
}

/// The feed's Calm button groups: a solid secondary tone (deepened a touch
/// in light mode, where secondaryContainer is close to the card).
Color _calmButtonColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return _isLight(cs)
      ? Color.alphaBlend(
          cs.primary.withValues(alpha: 0.10), cs.secondaryContainer)
      : cs.secondaryContainer;
}

/// Java's String.hashCode, so a subreddit gets the same avatar colour as in
/// the Android app.
int _javaHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (31 * h + c) & 0xFFFFFFFF;
  }
  return h >= 0x80000000 ? h - 0x100000000 : h;
}

final _flairShortcode = RegExp(r':[A-Za-z0-9_+\-]+:');
final _whitespace = RegExp(r'\s+');

/// Flair text without Reddit's `:emoji:` shortcodes (":Discussion:
/// Discussion" → "Discussion").
String cleanFlair(String text) =>
    text.replaceAll(_flairShortcode, ' ').replaceAll(_whitespace, ' ').trim();

/// A small icon matching common flair words (the flair's emoji images aren't
/// in its text).
IconData _flairIcon(String text) {
  final t = text.toLowerCase();
  if (t.contains('discuss')) return Icons.mode_comment_outlined;
  if (t.contains('question') || t.contains('help')) {
    return Icons.help_outline_rounded;
  }
  if (t.contains('news')) return Icons.newspaper_rounded;
  if (t.contains('meme') || t.contains('humor') || t.contains('funny')) {
    return Icons.sentiment_satisfied_rounded;
  }
  if (t == 'oc' ||
      t.contains('image') ||
      t.contains('photo') ||
      t.contains('art')) {
    return Icons.image_rounded;
  }
  if (t.contains('video')) return Icons.play_arrow_rounded;
  return Icons.sell_rounded;
}

/// Calm flair pill: 26 tall, icon + cleaned text. Nothing when it's only
/// emoji.
class CalmFlair extends StatelessWidget {
  const CalmFlair({super.key, required this.raw});
  final String raw;

  @override
  Widget build(BuildContext context) {
    final text = cleanFlair(raw);
    if (text.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: 8, right: 10),
      decoration: BoxDecoration(
          color: _calmControlColor(context),
          borderRadius: BorderRadius.circular(13)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_flairIcon(text), size: 14, color: cs.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// "Crossposted from r/x" (the media comes from the original post).
class CrosspostLine extends StatelessWidget {
  const CrosspostLine({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final from = post.crosspostFrom;
    if (from == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.repeat_rounded, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Crossposted from r/$from',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// "Reminder tomorrow at 09:00" on a post you asked to be reminded about
/// (cards and the post screen).
// TODO(reminders): tap to change or cancel (PostReminders.manage).
class ReminderLine extends ConsumerWidget {
  const ReminderLine({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = ref.watch(pendingReminderLabelProvider(post.id));
    if (when == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Reminder $when',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.primary)),
          ),
        ],
      ),
    );
  }
}

/// A poll's options, with results once Reddit shows them. Reddit's API can't
/// vote in polls: with the website sign-in, "Vote on Reddit" opens the post
/// signed in (the thread refreshes its results when you come back).
class PollOptions extends ConsumerWidget {
  const PollOptions({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = post;
    if (p.pollOptions.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final total = p.pollVotes.fold<int>(0, (a, b) => a + b);
    final n = p.pollOptions.length;
    final muted = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < n; i++)
            _option(cs, i, n, total),
          if (p.pollChoice != null)
            Text('You voted · ${compactNumber(total)} votes', style: muted)
          else if (p.pollVotes.isNotEmpty)
            Text('${compactNumber(total)} votes', style: muted)
          else if (ref.watch(webSignInProvider))
            TextButton(
              onPressed: () {
                RedditWeb.pollVoteOpened = p.id;
                context.push(RedditWeb.route(
                    'https://www.reddit.com${p.permalink}', 'Vote in poll'));
              },
              child: const Text('Vote on Reddit'),
            )
          else
            Text('Vote in the official app', style: muted),
        ],
      ),
    );
  }

  Widget _option(ColorScheme cs, int i, int n, int total) {
    final votes = i < post.pollVotes.length ? post.pollVotes[i] : null;
    final chosen = post.pollChoice == i;
    final share = votes != null && total > 0 ? votes / total : 0.0;
    // A segmented list: one block, round outside, tight between options.
    const big = Radius.circular(20), small = Radius.circular(4);
    final first = i == 0, last = i == n - 1;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 8 : 2),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: first ? big : small,
          topRight: first ? big : small,
          bottomLeft: last ? big : small,
          bottomRight: last ? big : small,
        ),
        child: ColoredBox(
          color: cs.surfaceContainerHigh,
          child: Stack(
            children: [
              if (votes != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: share,
                    child: ColoredBox(
                        color: chosen
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(post.pollOptions[i],
                          style: TextStyle(
                              fontWeight: chosen ? FontWeight.bold : null)),
                    ),
                    if (votes != null)
                      Text('${(share * 100).round()}%',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A subreddit avatar showing [imageUrl] or the first letter of [name].
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({
    super.key,
    required this.name,
    required this.size,
    required this.container,
    required this.content,
    this.imageUrl,
    this.fontSize,
    this.radius,
  });
  final String name;
  final double size;
  final Color container;
  final Color content;
  final String? imageUrl;
  final double? fontSize;
  final double? radius; // null = a circle

  @override
  Widget build(BuildContext context) {
    final letter = Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
          color: content,
          fontWeight: FontWeight.bold,
          fontSize: fontSize ?? size * 0.42),
    );
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 2),
      child: Container(
        width: size,
        height: size,
        color: container,
        alignment: Alignment.center,
        child: url == null
            ? letter
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context) * 2)
                        .round(),
                errorWidget: (_, __, ___) => Center(child: letter),
              ),
      ),
    );
  }
}

class _NsfwTag extends StatelessWidget {
  const _NsfwTag();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: cs.errorContainer, borderRadius: BorderRadius.circular(6)),
      child: Text('NSFW',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: cs.onErrorContainer)),
    );
  }
}

class CalmButton {
  const CalmButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.semanticLabel,
    this.toggled,
    this.tint,
    this.labelTint,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final String? semanticLabel;
  final bool? toggled; // the vote segments are toggles for screen readers
  final Color? tint; // a vote colour: fills the button at 22%, colours it
  final Color? labelTint;
}

/// M3 Expressive connected button group: 40 tall, outer corners round,
/// inner 6, 3 apart.
class CalmButtonGroup extends StatelessWidget {
  const CalmButtonGroup({super.key, required this.buttons});
  final List<CalmButton> buttons;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = _calmButtonColor(context);
    const height = 40.0;
    const r = Radius.circular(height / 2);
    const inner = Radius.circular(_calmInner);
    final last = buttons.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: _calmGap),
          Builder(builder: (_) {
            final b = buttons[i];
            final start = i == 0 ? r : inner;
            final end = i == last ? r : inner;
            final bg = b.tint != null
                ? Color.alphaBlend(b.tint!.withValues(alpha: 0.22), base)
                : base;
            final fg = b.tint ?? cs.onSecondaryContainer;
            return Semantics(
              button: true,
              toggled: b.toggled,
              label: b.semanticLabel,
              child: Material(
                color: bg,
                borderRadius: BorderRadiusDirectional.horizontal(
                        start: start, end: end)
                    .resolve(Directionality.of(context)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: b.onTap,
                  child: Container(
                    height: height,
                    padding: EdgeInsetsDirectional.only(
                        start: i == 0 ? 14 : 12, end: i == last ? 14 : 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(b.icon, size: 19, color: fg),
                        if (b.label != null) ...[
                          const SizedBox(width: 6),
                          Text(b.label!,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: b.labelTint ?? fg)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

/// A borderless icon button (Calm's share / save).
class CalmGhost extends StatelessWidget {
  const CalmGhost({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: 19, color: color, semanticLabel: label),
        ),
      );
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
          _miniBtn(Icons.arrow_upward_rounded,
              up ? votes.up : cs.onSurfaceVariant, 'Upvote', up, onUp),
          Text(compactNumber(score),
              style: TextStyle(fontWeight: FontWeight.w700, color: countColor)),
          _miniBtn(Icons.arrow_downward_rounded,
              down ? votes.down : cs.onSurfaceVariant, 'Downvote', down,
              onDown),
        ],
      ),
    );
  }

  // A toggle for screen readers ("Upvote, on").
  Widget _miniBtn(IconData icon, Color fg, String label, bool on,
          VoidCallback onTap) =>
      Semantics(
        toggled: on,
        child: IconButton(
          onPressed: onTap,
          tooltip: label,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon: Icon(icon, color: fg),
        ),
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
            color: Colors.white, size: 36, semanticLabel: 'Play'),
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
