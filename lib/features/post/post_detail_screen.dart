import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../foryou/for_you_learner.dart';
import '../history/thread_visits.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/route_observer.dart';
import '../../core/media_links.dart';
import '../../core/open_link.dart';
import '../../core/share.dart';
import '../../core/widgets/markdown_style.dart';
import '../../core/widgets/reddit_markdown.dart';
import '../../data/ai_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../feed/post_overrides.dart';
import '../feed/swipe_actions.dart';
import '../media/gallery_carousel.dart';
import '../media/media_viewers.dart';
import '../media/nsfw_blur.dart';
import '../settings/settings_controller.dart';
import 'comments_controller.dart';
import 'compose_sheet.dart';
import 'post_actions.dart';
import 'share_comment_image.dart';
import '../../core/widgets/error_view.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.subreddit,
    required this.postId,
    this.initialPost,
    this.focusCommentId,
  });

  final String subreddit;
  final String postId;
  final Post? initialPost;
  final String? focusCommentId; // open a single comment thread (from a permalink)

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen>
    with RouteAware {
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();
  List<Comment> _flat = const [];

  // In-post comment search.
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  // Matching comments by fullname, not list position: collapsing or loading
  // more replies shifts positions, which made stepping hit the wrong row or
  // throw a RangeError.
  List<String> _matchIds = [];
  int _matchPos = 0;
  String? _currentMatchId;

  // Reading time, counted only while the app is in the foreground and this
  // thread is the top route.
  final Stopwatch _dwell = Stopwatch();
  final Set<String> _dwellAwarded = {};
  late final AppLifecycleListener _lifecycle;
  late final ForYouLearner _learner;
  Post? _dwellPost;
  DateTime? _since; // previous visit to this thread; null on the first

  /// [c] and its parents up to the top-level comment, top first — the
  /// chain a "Share as image" card shows. Visible rows include every
  /// ancestor of a visible comment.
  List<Comment> _chainTo(Comment c) {
    final byName = {for (final x in _flat) x.fullname: x};
    final chain = [c];
    var parent = byName[c.parentId];
    while (parent != null && chain.length < 8) {
      chain.insert(0, parent);
      parent = byName[parent.parentId];
    }
    return chain;
  }

  bool _isNew(Comment c, String me) =>
      _since != null &&
      !c.isMore &&
      c.author != me &&
      c.created.isAfter(_since!);

  @override
  void initState() {
    super.initState();
    // Captured up front: learning also runs from dispose(), where ref is off
    // limits.
    _learner = ref.read(forYouLearnerProvider);
    // Remember the previous visit before recording this one: comments posted
    // since then are marked new.
    final visits = ref.read(threadVisitsProvider.notifier);
    _since = visits.lastVisit(widget.postId);
    visits.record(widget.postId);
    _dwell.start();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) =>
          s == AppLifecycleState.resumed ? _dwell.start() : _dwell.stop(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  // A pushed profile or subreddit covers the thread: pause, and learn from
  // what was read so far. Later time keeps accumulating when it's revealed.
  @override
  void didPushNext() {
    _dwell.stop();
    _learnFromDwell();
  }

  @override
  void didPopNext() => _dwell.start();

  /// Time in a thread is the strongest cheap signal there is: a post read for
  /// two minutes is a far stronger "more like this" than one backed out of at
  /// once. Each tier is awarded at most once per visit.
  void _learnFromDwell() {
    final post = _dwellPost;
    if (post == null) return;
    final seconds = _dwell.elapsed.inSeconds.clamp(0, 600);
    if (seconds < 3) {
      if (_dwellAwarded.isEmpty && _dwellAwarded.add('bounce')) {
        _learner.bounce(post);
      }
      return;
    }
    if (seconds >= 30 && _dwellAwarded.add('read')) _learner.read(post);
    if (seconds >= 120 && _dwellAwarded.add('longRead')) {
      _learner.read(post, long: true);
    }
  }

  @override
  void dispose() {
    _dwell.stop();
    _learnFromDwell();
    _lifecycle.dispose();
    appRouteObserver.unsubscribe(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _matchIds = [];
        _currentMatchId = null;
      }
    });
  }

  void _runSearch(String raw) {
    final q = raw.trim().toLowerCase();
    final m = <String>[];
    if (q.isNotEmpty) {
      for (final c in _flat) {
        if (!c.isMore && c.body.toLowerCase().contains(q)) m.add(c.fullname);
      }
    }
    setState(() {
      _matchIds = m;
      _matchPos = 0;
      _currentMatchId = m.isEmpty ? null : m.first;
    });
    if (m.isNotEmpty) _scrollToMatch();
  }

  void _scrollToMatch() {
    if (_matchIds.isEmpty) return;
    _currentMatchId = _matchIds[_matchPos];
    // Resolve against the list as it is now; a match hidden inside a
    // collapsed thread has no row to scroll to.
    final ci = _flat.indexWhere((c) => c.fullname == _currentMatchId);
    if (ci < 0) return;
    _itemScroll.scrollTo(
        index: ci + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.12);
  }

  void _stepMatch(int delta) {
    if (_matchIds.isEmpty) return;
    setState(() =>
        _matchPos = (_matchPos + delta + _matchIds.length) % _matchIds.length);
    _scrollToMatch();
  }

  Future<void> _summarize(Post post) async {
    final key = ref.read(openAiKeyProvider).valueOrNull;
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add an OpenAI key in Settings → AI summaries.')));
      return;
    }
    final s = ref.read(settingsControllerProvider);
    final baseUrl =
        s.aiUseCustomUrl ? s.aiBaseUrl : 'https://api.openai.com';
    final style = SummaryStyle
        .values[s.aiSummaryStyle.clamp(0, SummaryStyle.values.length - 1)];
    final threadText = AiService.buildThreadText(post, _flat, s.aiMaxChars);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SummarySheet(
        baseUrl: baseUrl,
        apiKey: key,
        model: s.aiModel,
        style: style,
        threadText: threadText,
      ),
    );
  }

  /// Jumps the comment list to the next top-level (depth 0) comment, cycling
  /// back to the first once past the last. List index 0 is the post header, so
  /// comment `ci` lives at list index `ci + 1`.
  void _jumpNextTopLevel() => _jumpNext((c) => c.depth == 0);

  /// Long-press on the ↓ button: jump by the original poster or your own
  /// comments instead of top-level ones.
  void _showJumpMenu(String opAuthor, String me, {bool hasNew = false}) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, icon, test) in [
              ('Next top-level comment', Icons.keyboard_arrow_down_rounded,
                  (Comment c) => c.depth == 0),
              if (hasNew)
                ('Next new comment', Icons.fiber_new_rounded,
                    (Comment c) => _isNew(c, me)),
              ('Next comment by OP', Icons.record_voice_over_rounded,
                  (Comment c) => c.author == opAuthor),
              if (me.isNotEmpty)
                ('Next of your comments', Icons.person_rounded,
                    (Comment c) => c.author == me),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () {
                  Navigator.pop(sheet);
                  if (!_jumpNext(test)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No such comment here')));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Scrolls to the next comment below the current top that passes [match],
  /// wrapping to the first. False when none in the thread does.
  bool _jumpNext(bool Function(Comment) match, {bool backwards = false}) {
    if (_flat.isEmpty) return false;

    // Reference = the topmost item actually on screen (ignore the cached items
    // ScrollablePositionedList keeps just outside the viewport).
    final onScreen = _itemPositions.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1);
    final topIndex = onScreen.isEmpty
        ? 0
        : onScreen.map((p) => p.index).reduce((a, b) => a < b ? a : b);

    // List index of every matching comment (comment ci is at ci + 1).
    final hits = [
      for (var ci = 0; ci < _flat.length; ci++)
        if (!_flat[ci].isMore && match(_flat[ci])) ci + 1
    ];
    if (hits.isEmpty) return false;
    // The nearest one below the current top (or above, going back), wrapping
    // round at the ends.
    final int target = backwards
        ? hits.lastWhere((i) => i < topIndex, orElse: () => hits.last)
        : hits.firstWhere((i) => i > topIndex, orElse: () => hits.first);

    _itemScroll.scrollTo(
      index: target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.0,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.focusCommentId != null
        ? '${widget.subreddit}/${widget.postId}/focus_${widget.focusCommentId}'
        : '${widget.subreddit}/${widget.postId}';
    final async = ref.watch(commentsControllerProvider(key));
    final notifier = ref.read(commentsControllerProvider(key).notifier);
    final username =
        ref.watch(authControllerProvider).valueOrNull?.username ?? '';
    final thread = async.valueOrNull;
    _dwellPost = thread?.post ?? widget.initialPost;
    // Flattened up front: the bottom toolbar needs it before the list builds.
    if (thread != null) _flat = _flatten(thread.comments, thread.collapsed);
    final hasAiKey =
        ref.watch(openAiKeyProvider).valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(thread?.post.subredditPrefixed ??
            (widget.subreddit == '_' ? 'Post' : 'r/${widget.subreddit}')),
        actions: [
          if (thread != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort comments',
              onSelected: notifier.changeSort,
              itemBuilder: (_) => [
                for (final s in commentSorts)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: notifier.sort == s,
                    child: Text(commentSortLabels[s] ?? s),
                  ),
              ],
            ),
          if (thread != null)
            IconButton(
              tooltip: 'Search comments',
              icon: Icon(
                  _searchOpen ? Icons.search_off_rounded : Icons.search_rounded),
              onPressed: _toggleSearch,
            ),
          if (thread != null)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => showPostActionsSheet(context, ref, thread.post,
                  onSummarize:
                      hasAiKey ? () => _summarize(thread.post) : null),
            ),
          if (thread != null && thread.post.author == username)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final post = thread.post;
                if (v == 'edit' && post.isSelf) {
                  final newText = await showEditSheet(context, ref,
                      thingFullname: post.fullname, initialText: post.selftext);
                  if (newText != null) notifier.applyEdit(post.fullname, newText);
                } else if (v == 'delete') {
                  final ok = await _confirmDelete(context, 'post');
                  if (ok) {
                    await ref
                        .read(redditRepositoryProvider)
                        .deleteThing(post.fullname);
                    if (context.mounted) Navigator.of(context).maybePop();
                  }
                }
              },
              itemBuilder: (_) => [
                if (thread.post.isSelf)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      floatingActionButton: thread == null
          ? null
          : _ThreadToolbar(
              newCount: _flat.where((c) => _isNew(c, username)).length,
              hasMine: username.isNotEmpty &&
                  _flat.any((c) => c.author == username),
              hasComments: thread.comments.isNotEmpty,
              onPrevNew: () =>
                  _jumpNext((c) => _isNew(c, username), backwards: true),
              onNextNew: () => _jumpNext((c) => _isNew(c, username)),
              onMine: () => _jumpNext((c) => c.author == username),
              onComment: () async {
                final reply = await showReplySheet(context, ref,
                    parentFullname: thread.post.fullname, parentDepth: -1);
                if (reply != null) {
                  notifier.insertReply(thread.post.fullname, reply);
                  ref
                      .read(postOverridesProvider.notifier)
                      .bumpComments(thread.post, 1);
                  // Commenting is the strongest engagement signal we have.
                  ref.read(forYouLearnerProvider).comment(thread.post);
                }
              },
              onNext: _jumpNextTopLevel,
              onNextLongPress: () => _showJumpMenu(
                  thread.post.author, username,
                  hasNew: _flat.any((c) => _isNew(c, username))),
            ),
      body: Stack(
        children: [
          async.when(
        loading: () => _LoadingWithHeader(post: widget.initialPost),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load this post.\n${friendlyError(e)}',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: notifier.refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (thread) {
          final flat = _flat; // flattened at the top of build()
          final list = RefreshIndicator(
            onRefresh: notifier.refresh,
            child: ScrollablePositionedList.builder(
              itemScrollController: _itemScroll,
              itemPositionsListener: _itemPositions,
              // Build comments about a screen ahead, so scrolling shows
              // ready-made rows instead of building them mid-frame.
              minCacheExtent: 900,
              padding: const EdgeInsets.only(top: 6, bottom: 96),
              itemCount: 1 + (flat.isEmpty ? 1 : flat.length),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _PostHeader(post: thread.post, fresh: true);
                }
                if (flat.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('No comments yet')),
                  );
                }
                final c = flat[index - 1];
                return _CommentTile(
                  key: ValueKey(c.fullname),
                  comment: c,
                  highlighted: _currentMatchId == c.fullname,
                  isNew: _isNew(c, username),
                  isOwn: c.author == username,
                  opAuthor: thread.post.author,
                  collapsed: thread.collapsed.contains(c.id),
                  loadingMore: thread.loadingMore.contains(c.fullname),
                  onToggle: () => notifier.toggleCollapse(c.id),
                  // A "more" stub with no children ids is Reddit's "continue
                  // this thread": the replies are too deep to fetch here, so
                  // open that branch in single-comment focus mode.
                  onLoadMore: c.moreChildren.isEmpty &&
                          c.parentId.startsWith('t1_')
                      ? () => context.push(
                          '/comments/${thread.post.subreddit}/${thread.post.id}'
                          '?comment=${c.parentId.replaceFirst('t1_', '')}')
                      : () => notifier.loadMore(c),
                  onUpdate: (change) =>
                      notifier.updateComment(c.fullname, change),
                  onShareImage: () => showShareCommentImage(context,
                      post: thread.post, chain: _chainTo(c)),
                  onReply: () async {
                    final reply = await showReplySheet(context, ref,
                        parentFullname: c.fullname,
                        parentDepth: c.depth,
                        replyingTo: c.author);
                    if (reply != null) {
                      notifier.insertReply(c.fullname, reply);
                      ref
                          .read(postOverridesProvider.notifier)
                          .bumpComments(thread.post, 1);
                      ref.read(forYouLearnerProvider).comment(thread.post);
                    }
                  },
                  onEdit: () async {
                    final newText = await showEditSheet(context, ref,
                        thingFullname: c.fullname, initialText: c.body);
                    if (newText != null) notifier.applyEdit(c.fullname, newText);
                  },
                  onDelete: () async {
                    final ok = await _confirmDelete(context, 'comment');
                    if (ok) {
                      await ref
                          .read(redditRepositoryProvider)
                          .deleteThing(c.fullname);
                      notifier.removeComment(c.fullname);
                    }
                  },
                );
              },
            ),
          );
          if (widget.focusCommentId == null) return list;
          // Single-comment view (from an inbox reply / permalink).
          final cs = Theme.of(context).colorScheme;
          return Column(
            children: [
              Material(
                color: cs.secondaryContainer,
                child: InkWell(
                  onTap: () => context
                      .replace('/comments/${widget.subreddit}/${widget.postId}'),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.subdirectory_arrow_right_rounded,
                            size: 18, color: cs.onSecondaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Viewing a single comment thread',
                              style: TextStyle(
                                  color: cs.onSecondaryContainer,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('Show all',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: list),
            ],
          );
        },
          ),
          if (_searchOpen && thread != null)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: _buildSearchBar(context),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _matchIds.length;
    final has = _searchCtrl.text.trim().isNotEmpty;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 6),
            Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _runSearch,
                onSubmitted: (_) => _stepMatch(1),
                decoration: const InputDecoration(
                  hintText: 'Search comments',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (has)
              Text(total == 0 ? '0/0' : '${_matchPos + 1}/$total',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            IconButton(
              tooltip: 'Previous',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: total == 0 ? null : () => _stepMatch(-1),
            ),
            IconButton(
              tooltip: 'Next',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: total == 0 ? null : () => _stepMatch(1),
            ),
            IconButton(
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              onPressed: _toggleSearch,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a link tapped inside a comment: media plays/shows in-app, reddit links
/// route in-app, everything else goes to the browser.
/// Inline previews for any media linked in a comment body (images, gifs,
/// videos), so comments don't just show a bare URL that opens a browser.
class _CommentMedia extends StatelessWidget {
  const _CommentMedia({required this.body, this.extra = const []});
  final String body;
  // Media resolved from media_metadata (see splitMediaRefs), shown first.
  final List<Uri> extra;

  @override
  Widget build(BuildContext context) {
    final links = [...extra, ...extractMediaLinks(body)];
    if (links.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cap it so a link-heavy comment can't blow up the list.
          for (final uri in links.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => openLink(context, uri.toString()),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: isVideoUrl(uri)
                            ? Container(
                                height: 120,
                                width: double.infinity,
                                color: cs.surfaceContainerHighest,
                              )
                            : CachedNetworkImage(
                                imageUrl: uri.toString(),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                placeholder: (_, __) => Container(
                                    height: 120,
                                    color: cs.surfaceContainerHighest),
                                errorWidget: (_, __, ___) => Container(
                                  height: 60,
                                  color: cs.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Text('Could not load media',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant)),
                                ),
                              ),
                      ),
                      if (isVideoUrl(uri))
                        Icon(Icons.play_circle_fill_rounded,
                            size: 48, color: cs.onSurface.withValues(alpha: .8)),
                      if (isGifUrl(uri))
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('GIF',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Runs an AI thread summary and shows the result (markdown) with copy.
class _SummarySheet extends StatefulWidget {
  const _SummarySheet({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.style,
    required this.threadText,
  });
  final String baseUrl;
  final String apiKey;
  final String model;
  final SummaryStyle style;
  final String threadText;

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  bool _loading = true;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await AiService.summarize(
        baseUrl: widget.baseUrl,
        apiKey: widget.apiKey,
        model: widget.model,
        style: widget.style,
        threadText: widget.threadText,
      );
      if (mounted) {
        setState(() {
          _result = out;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI summary · ${widget.style.label}',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (_result != null)
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _result!));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Copied')));
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null) ...[
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _run, child: const Text('Retry')),
          ] else
            MarkdownBody(data: _result ?? ''),
          if (!_loading && _error == null) ...[
            const SizedBox(height: 16),
            Text('Generated by ${widget.model}. AI summaries can be wrong.',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Depth-edge colors (rotate by nesting level).
const _railColors = [
  Color(0xFF9F8BE8),
  Color(0xFF62B5AA),
  Color(0xFFE0A55C),
  Color(0xFFD88FB4),
  Color(0xFF7E9BE0),
];

List<Comment> _flatten(List<Comment> nodes, Set<String> collapsed) {
  final out = <Comment>[];
  void walk(Comment c) {
    out.add(c);
    if (!c.isMore && !collapsed.contains(c.id)) {
      for (final r in c.replies) {
        walk(r);
      }
    }
  }

  for (final c in nodes) {
    walk(c);
  }
  return out;
}

Future<bool> _confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $what?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete')),
      ],
    ),
  );
  return ok ?? false;
}

/// Everything that moves through the thread in ONE compact floating pill
/// (as in Scoops), instead of a stack of large buttons:
/// [↑ N new ↓] [your comment] [comment] [● next top-level].
class _ThreadToolbar extends StatelessWidget {
  const _ThreadToolbar({
    required this.newCount,
    required this.hasMine,
    required this.hasComments,
    required this.onPrevNew,
    required this.onNextNew,
    required this.onMine,
    required this.onComment,
    required this.onNext,
    required this.onNextLongPress,
  });

  final int newCount;
  final bool hasMine;
  final bool hasComments;
  final VoidCallback onPrevNew, onNextNew, onMine, onComment, onNext;
  final VoidCallback onNextLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = cs.onPrimaryContainer;
    Widget icon(IconData i, String tip, VoidCallback f) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          color: on,
          onPressed: f,
          icon: Icon(i, size: 22),
        );

    return Material(
      color: cs.primaryContainer,
      elevation: 3,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (newCount > 0)
              // The new-comments stepper, on its own tonal segment.
              Container(
                height: 40,
                decoration: ShapeDecoration(
                    color: on.withValues(alpha: 0.08),
                    shape: const StadiumBorder()),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  icon(Icons.keyboard_arrow_up_rounded, 'Previous new comment',
                      onPrevNew),
                  Text('$newCount new',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: on)),
                  icon(Icons.keyboard_arrow_down_rounded, 'Next new comment',
                      onNextNew),
                ]),
              ),
            if (hasMine) icon(Icons.person_rounded, 'Your comments', onMine),
            icon(Icons.add_comment_rounded, 'Comment', onComment),
            if (hasComments)
              // The main action: a filled accent circle. Long-press for the
              // jump menu (OP / yours / new).
              GestureDetector(
                onLongPress: onNextLongPress,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onNext,
                    child: Tooltip(
                      message: 'Next top-level comment (long-press for more)',
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: cs.onPrimary),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingWithHeader extends StatelessWidget {
  const _LoadingWithHeader({this.post});
  final Post? post;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (post != null) _PostHeader(post: post!, fresh: false),
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}

class _PostHeader extends ConsumerStatefulWidget {
  const _PostHeader({required this.post, required this.fresh});
  final Post post;
  // True for the post as just fetched with its comments. False for the feed's
  // copy shown while loading, which can be stale and must not be synced.
  final bool fresh;
  @override
  ConsumerState<_PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends ConsumerState<_PostHeader> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_PostHeader old) {
    super.didUpdateWidget(old);
    if (!identical(old.post, widget.post)) _sync(); // e.g. pull-to-refresh
  }

  // Seed the shared overrides from a fresh fetch (score, vote, comment count)
  // so the feed card reflects it when you go back.
  void _sync() {
    if (!widget.fresh) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(postOverridesProvider.notifier).syncFromServer(widget.post);
      }
    });
  }

  Future<void> _vote(int dir) async {
    final overrides = ref.read(postOverridesProvider.notifier);
    final cur = overrides.effective(widget.post);
    final current = cur.likes == true ? 1 : (cur.likes == false ? -1 : 0);
    final target = current == dir ? 0 : dir;
    overrides.setVote(widget.post, target);
    // Same learning as a vote on the card (this one used to skip keywords).
    final learner = ref.read(forYouLearnerProvider)
      ..vote(widget.post, current, target);
    try {
      await ref.read(redditRepositoryProvider).vote(widget.post.fullname, target);
    } catch (e) {
      learner.vote(widget.post, target, current);
      overrides.setVote(widget.post, current);
      if (mounted) showActionError(context, 'vote', e);
    }
  }

  void _openMedia() {
    final p = widget.post;
    switch (p.type) {
      case PostType.image:
        openImageViewer(context, p.previewUrl ?? p.url, title: p.title);
      case PostType.gif:
        if (p.gifMp4Url != null) {
          openVideoViewer(context, p.gifMp4Url!,
              title: p.title, downloadUrl: p.gifMp4Url, externalUrl: p.url);
        } else {
          openImageViewer(context, p.url, title: p.title);
        }
      case PostType.gallery:
        openGalleryViewer(context, p.gallery, title: p.title);
      case PostType.video:
        openPostVideo(context, p);
      case PostType.link:
        openInBrowser(context, Uri.parse(p.url));
      case PostType.self:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/r/${p.subreddit}'),
            child: Text(p.subredditPrefixed,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: cs.primary)),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => context.push('/u/${p.author}'),
            child: Text('u/${p.author} · ${timeAgo(p.created)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 12),
          Text(p.title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
          if (p.linkFlairText != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.linkFlairText!,
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ],
          if (p.crosspostFrom != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.repeat_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Crossposted from r/${p.crosspostFrom}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _media(cs),
          if (p.pollOptions.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final opt in p.pollOptions)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(opt),
              ),
            Text('Vote in the official app',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
          // Gallery/image/link posts can carry a body too — show it whenever
          // there's selftext, not only for pure self-posts.
          if (p.selftext.isNotEmpty)
            RedditMarkdown(
              data: p.selftext,
              selectable: true,
              styleSheet: redditMarkdownStyle(context),
              onTapLink: (_, href, __) => openLink(context, href),
            ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final ov =
                ref.watch(postOverridesProvider.select((m) => m[p.id]));
            final likes = ov != null ? ov.likes : p.likes;
            final score = ov?.score ?? p.score;
            final saved = ov?.saved ?? p.saved;
            final numComments = ov?.numComments ?? p.numComments;
            return Row(
              children: [
                _VotePill(
                    score: score,
                    likes: likes,
                    onUp: () => _vote(1),
                    onDown: () => _vote(-1)),
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.mode_comment_outlined, size: 18),
                  label: Text(compactNumber(numComments)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    final overrides =
                        ref.read(postOverridesProvider.notifier);
                    final next = !overrides.effective(p).saved;
                    overrides.setSaved(p, next);
                    final learner = ref.read(forYouLearnerProvider)
                      ..save(p, next);
                    try {
                      await ref
                          .read(redditRepositoryProvider)
                          .setSaved(p.fullname, next);
                    } catch (e) {
                      overrides.setSaved(p, !next);
                      learner.save(p, !next);
                      if (context.mounted) {
                        showActionError(
                            context, next ? 'save' : 'unsave', e);
                      }
                    }
                  },
                  color: saved ? cs.primary : null,
                  icon: Icon(saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded),
                ),
              ],
            );
          }),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _media(ColorScheme cs) {
    final p = widget.post;
    if (p.type == PostType.self) return const SizedBox.shrink();
    final blur = (p.over18 && ref.watch(settingsControllerProvider).blurNsfw) || p.spoiler;
    if (p.type == PostType.gallery && p.gallery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NsfwBlur(
          blur: blur,
          child: GalleryCarousel(images: p.gallery, title: p.title),
        ),
      );
    }
    if (p.type == PostType.link) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: _openMedia,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(p.domain, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    final url = p.previewUrl ??
        ((p.type == PostType.image || p.type == PostType.gif) ? p.url : null) ??
        (p.gallery.isNotEmpty ? p.gallery.first.url : null);
    final aspect = (p.previewWidth != null &&
            p.previewHeight != null &&
            p.previewHeight! > 0)
        ? (p.previewWidth! / p.previewHeight!).clamp(0.5, 2.0)
        : 16 / 9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NsfwBlur(
        blur: blur,
        blurredImageUrl: p.blurredPreviewUrl,
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
                  CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                else
                  Container(color: cs.surfaceContainerHighest),
                if (p.type == PostType.video)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _CommentTile extends ConsumerStatefulWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.isOwn,
    required this.opAuthor,
    required this.collapsed,
    required this.loadingMore,
    required this.onToggle,
    required this.onLoadMore,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onUpdate,
    required this.onShareImage,
    this.highlighted = false,
    this.isNew = false,
  });

  final Comment comment;
  final bool isOwn;
  final String opAuthor;
  final bool collapsed;
  final bool loadingMore;
  final bool highlighted; // current in-post search match
  final bool isNew; // posted since the user's last visit to this thread
  final VoidCallback onToggle;
  final VoidCallback onLoadMore;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  // Writes vote/save state into the comment tree (CommentsController).
  final void Function(Comment Function(Comment)) onUpdate;
  final VoidCallback onShareImage;

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile> {
  Future<void> _vote(int dir) async {
    final before = widget.comment;
    final current = before.likes == true ? 1 : (before.likes == false ? -1 : 0);
    final target = current == dir ? 0 : dir;
    widget.onUpdate((c) => c.copyWith(
        score: c.score + target - current,
        likes: target == 1 ? true : (target == -1 ? false : null)));
    try {
      await ref.read(redditRepositoryProvider).vote(before.fullname, target);
    } catch (e) {
      widget.onUpdate(
          (c) => c.copyWith(score: before.score, likes: before.likes));
      if (mounted) showActionError(context, 'vote', e);
    }
  }

  /// What a swipe on this comment does, per Settings → Swipe actions.
  SwipeSpec? _swipe(SwipeAction action) {
    final votes = Theme.of(context).extension<VoteColors>()!;
    final cs = Theme.of(context).colorScheme;
    return switch (action) {
      SwipeAction.upvote => SwipeSpec(action.icon, votes.up, () => _vote(1)),
      SwipeAction.downvote =>
        SwipeSpec(action.icon, votes.down, () => _vote(-1)),
      SwipeAction.save => SwipeSpec(action.icon, cs.primary, _toggleSave),
      SwipeAction.reply =>
        SwipeSpec(action.icon, cs.tertiary, widget.onReply),
      SwipeAction.collapse =>
        SwipeSpec(action.icon, cs.secondary, widget.onToggle),
      SwipeAction.hide || SwipeAction.none => null,
    };
  }

  Future<void> _toggleSave() async {
    final next = !widget.comment.saved;
    widget.onUpdate((c) => c.copyWith(saved: next));
    try {
      await ref
          .read(redditRepositoryProvider)
          .setSaved(widget.comment.fullname, next);
    } catch (e) {
      widget.onUpdate((c) => c.copyWith(saved: !next));
      if (mounted) showActionError(context, next ? 'save' : 'unsave', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final split = splitMediaRefs(comment.body, comment.media);
    final tapToCollapse = ref.watch(
        settingsControllerProvider.select((s) => s.tapToCollapse));
    final cs = Theme.of(context).colorScheme;
    final depth = comment.depth;
    final indent = depth.clamp(0, 6) * 12.0;

    // "Load more replies" node — a light indented row, not a card.
    if (comment.isMore) {
      return Padding(
        padding: EdgeInsets.fromLTRB(10 + indent, 0, 10, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.loadingMore ? null : widget.onLoadMore,
            icon: widget.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.add_circle_outline_rounded,
                    size: 18, color: cs.primary),
            label: Text(comment.moreChildren.isEmpty
                ? 'Continue thread →'
                : '${comment.moreCount} more replies'),
          ),
        ),
      );
    }

    final isMod = comment.distinguished == 'moderator';
    final nameColor =
        isMod ? Colors.green : (widget.isOwn ? cs.primary : cs.onSurface);
    final edge = _railColors[(depth - 1).clamp(0, _railColors.length - 1)];

    final settings = ref.watch(settingsControllerProvider);
    return SwipeActions(
      enabled: settings.swipeActions,
      start: _swipe(settings.swipeCommentStart),
      end: _swipe(settings.swipeCommentEnd),
      child: Container(
        margin: EdgeInsets.fromLTRB(10 + indent, 0, 10, 8),
        decoration: BoxDecoration(
          color: widget.highlighted
              ? cs.primaryContainer
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: widget.highlighted
              ? Border.all(color: cs.primary, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 1)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        // A Stack, not IntrinsicHeight + Row: stretching the depth bar to the
        // comment's height cost a second layout pass for every comment, every
        // time one scrolled into view.
        child: Stack(
          children: [
              Padding(
                padding: EdgeInsetsDirectional.only(start: depth > 0 ? 4 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Long-press collapses the whole subtree; tap re-expands a
                    // collapsed comment (so a tap can't accidentally collapse).
                    InkWell(
            onTap: widget.collapsed || tapToCollapse ? widget.onToggle : null,
            onLongPress: () {
              HapticFeedback.selectionClick();
              widget.onToggle();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  // Tapping the avatar/name opens the commenter's profile.
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: comment.author == '[deleted]'
                          ? null
                          : () => context.push('/u/${comment.author}'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AuthorDot(name: comment.author, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'u/${comment.author}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: nameColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (comment.author == widget.opAuthor &&
                      comment.author != '[deleted]') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('OP',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text('· ${timeAgo(comment.created)}',
                      style:
                          TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  if (widget.isNew) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('NEW',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: cs.onTertiaryContainer)),
                    ),
                  ],
                  const Spacer(),
                  if (widget.collapsed)
                    Icon(Icons.unfold_more_rounded,
                        size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (!widget.collapsed) ...[
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: tapToCollapse ? widget.onToggle : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RedditMarkdown(
                      data: split.text,
                      // Plain text: a selectable paragraph is a full text
                      // editor widget, far heavier to build while scrolling
                      // through hundreds of comments (it also swallowed taps
                      // for tap-to-collapse). "Copy text" is in the ⋯ menu.
                      selectable: false,
                      styleSheet: redditMarkdownStyle(context),
                      onTapLink: (_, href, __) =>
                          openLink(context, href),
                    ),
                    _CommentMedia(body: comment.body, extra: split.media),
                  ],
                ),
              ),
            ),
            _actions(cs),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 12, 8),
              child: Text(
                comment.body.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
              ),
            ),
                  ],
                ),
              ),
              // Colored depth edge (only on replies), full height.
              if (depth > 0)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: ColoredBox(color: edge.withValues(alpha: 0.9)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _actions(ColorScheme cs) {
    final votes = Theme.of(context).extension<VoteColors>()!;
    final up = widget.comment.likes == true;
    final down = widget.comment.likes == false;
    final scoreColor = up ? votes.up : (down ? votes.down : cs.onSurfaceVariant);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => _vote(1),
          icon: Icon(Icons.arrow_upward_rounded,
              color: up ? votes.up : cs.onSurfaceVariant),
        ),
        Text(
          widget.comment.scoreHidden
              ? '–'
              : compactNumber(widget.comment.score),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: scoreColor),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => _vote(-1),
          icon: Icon(Icons.arrow_downward_rounded,
              color: down ? votes.down : cs.onSurfaceVariant),
        ),
        _CommentActionBtn(
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: widget.onReply,
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: 'Collapse thread',
          onPressed: widget.onToggle,
          color: cs.onSurfaceVariant,
          icon: const Icon(Icons.unfold_less_rounded),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: _toggleSave,
          color: widget.comment.saved ? cs.primary : cs.onSurfaceVariant,
          icon: Icon(widget.comment.saved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded,
              size: 18, color: cs.onSurfaceVariant),
          padding: EdgeInsets.zero,
          onSelected: (v) {
            switch (v) {
              case 'copy':
                Clipboard.setData(ClipboardData(text: widget.comment.body));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')));
              case 'share':
                shareUrl(context, 'https://reddit.com${widget.comment.permalink}');
              case 'image':
                widget.onShareImage();
              case 'edit':
                widget.onEdit();
              case 'delete':
                widget.onDelete();
              case 'block':
                confirmBlockUser(context, ref, widget.comment.author);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('Copy text')),
            if (widget.comment.permalink.isNotEmpty)
              const PopupMenuItem(value: 'share', child: Text('Share')),
            const PopupMenuItem(value: 'image', child: Text('Share as image')),
            if (widget.isOwn) ...[
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
            if (!widget.isOwn && widget.comment.author != '[deleted]')
              PopupMenuItem(
                  value: 'block', child: Text('Block u/${widget.comment.author}')),
          ],
        ),
      ],
    );
  }
}

class _CommentActionBtn extends StatelessWidget {
  const _CommentActionBtn(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

/// Small colored avatar with the author's initial (color derived from name).
class _AuthorDot extends StatelessWidget {
  const _AuthorDot({required this.name, this.size = 20});
  final String name;
  final double size;

  static const _palette = [
    Color(0xFF7C5CE0),
    Color(0xFF4FA89B),
    Color(0xFFC77E4A),
    Color(0xFFC46A96),
    Color(0xFF5B82CE),
    Color(0xFF5FA85A),
  ];

  @override
  Widget build(BuildContext context) {
    final clean = name.replaceFirst('u/', '');
    final deleted = clean.isEmpty || clean.startsWith('[');
    var h = 0;
    for (final r in clean.codeUnits) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    final color =
        deleted ? Theme.of(context).colorScheme.outline : _palette[h % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        deleted ? '?' : clean[0].toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.5),
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
    return Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onUp,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(Icons.arrow_upward_rounded,
                color: up ? votes.up : cs.onSurfaceVariant),
          ),
          Text(compactNumber(score),
              style: TextStyle(fontWeight: FontWeight.w700, color: countColor)),
          IconButton(
            onPressed: onDown,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(Icons.arrow_downward_rounded,
                color: down ? votes.down : cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
