import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/theme/motion.dart';
import '../../core/widgets/loading.dart';
import '../../core/widgets/pick_one_menu.dart';
import '../../core/widgets/toggles.dart';
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
import '../../core/theme/app_theme.dart';
import '../../models/comment.dart';
import '../../models/flair.dart';
import '../../models/post.dart';
import '../../models/subreddit.dart';
import '../auth/auth_controller.dart';
import '../feed/local_votes.dart';
import '../feed/post_card.dart';
import '../feed/post_overrides.dart';
import '../feed/swipe_actions.dart';
import '../media/gallery_carousel.dart';
import '../media/media_viewers.dart';
import '../media/nsfw_blur.dart';
import '../media/pause_while_scrolling.dart';
import '../reminders/post_reminders.dart';
import '../settings/settings_controller.dart';
import '../web/reddit_web_screen.dart';
import 'comment_tree.dart';
import 'comments_controller.dart';
import 'ask_thread_sheet.dart';
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
  Post? _post;

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

  String get _key => widget.focusCommentId != null
      ? '${widget.subreddit}/${widget.postId}/focus_${widget.focusCommentId}'
      : '${widget.subreddit}/${widget.postId}';

  CommentsController get _notifier =>
      ref.read(commentsControllerProvider(_key).notifier);

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
    // After this frame: a provider can't change while the tree builds.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => visits.record(widget.postId));
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
  void didPopNext() {
    _dwell.start();
    // Back from voting in this post's poll on Reddit: load the results.
    if (RedditWeb.pollVoteOpened == widget.postId) {
      RedditWeb.pollVoteOpened = null;
      _refresh();
    }
  }

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

  /// A reply just posted, or a comment an AI answer cites: once it's in the
  /// list, scroll to it and highlight it for a moment (the search
  /// highlight).
  Future<void> _reveal(String fullname) async {
    var ci = -1;
    // Wait (up to 2s) for the row to appear in the list.
    for (var i = 0; i < 20 && mounted; i++) {
      ci = _flat.indexWhere((c) => c.fullname == fullname);
      if (ci >= 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (ci < 0 || !mounted) return;
    setState(() => _currentMatchId = fullname);
    await _itemScroll.scrollTo(
        index: ci + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.25);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (mounted && _currentMatchId == fullname && !_searchOpen) {
      setState(() => _currentMatchId = null);
    }
  }

  /// Long-press on the ↓ button: jump by the original poster or your own
  /// comments instead of top-level ones.
  void _showJumpMenu(String opAuthor, String me, {bool hasNew = false}) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: sheetMotion,
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
  /// wrapping to the first. False when none in the thread does. List index 0
  /// is the post header, so comment `ci` lives at list index `ci + 1`.
  bool _jumpNext(bool Function(Comment) match, {bool backwards = false}) {
    if (_flat.isEmpty) return false;

    // Reference = the topmost item actually on screen (ignore the cached items
    // ScrollablePositionedList keeps just outside the viewport).
    final onScreen = _itemPositions.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1);
    final topIndex = onScreen.isEmpty
        ? 0
        : onScreen.map((p) => p.index).reduce((a, b) => a < b ? a : b);

    final hits = [
      for (var ci = 0; ci < _flat.length; ci++)
        if (!_flat[ci].isMore && match(_flat[ci])) ci + 1
    ];
    if (hits.isEmpty) return false;
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

  Future<void> _refresh() async {
    try {
      await _notifier.refresh();
    } catch (e) {
      // A failed refresh keeps the thread (and its collapsed comments)
      // readable.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Couldn't refresh: ${friendlyError(e)}"),
        action: SnackBarAction(label: 'Retry', onPressed: _refresh),
      ));
    }
  }

  // ---------------------------------------------------------------- actions

  void _onReplied(String parent, Comment reply) {
    final p = _post;
    if (p == null) return;
    _notifier.insertReply(parent, reply);
    // The new comment lands at the top of the thread or under its parent —
    // often off-screen, so it looked like nothing happened. Bring it in.
    _reveal(reply.fullname);
    ref.read(postOverridesProvider.notifier).bumpComments(p, 1);
    // Commenting is the strongest engagement signal we have.
    ref.read(forYouLearnerProvider).comment(p);
  }

  Future<void> _replyToPost() async {
    final p = _post;
    if (p == null) return;
    final reply = await showReplySheet(context, ref,
        parentFullname: p.fullname, parentDepth: -1, post: p);
    if (reply != null) _onReplied(p.fullname, reply);
  }

  Future<void> _reply(Comment c) async {
    final reply = await showReplySheet(context, ref,
        parentFullname: c.fullname,
        parentDepth: c.depth,
        replyingTo: c.author,
        post: _post);
    if (reply != null) _onReplied(c.fullname, reply);
  }

  Future<void> _edit(Comment c) async {
    final text = await showEditSheet(context, ref,
        thingFullname: c.fullname, initialText: c.body);
    if (text != null) _notifier.applyEdit(c.fullname, text);
  }

  Future<void> _delete(Comment c) async {
    if (!await _confirmDelete(context, 'comment')) return;
    try {
      await ref.read(redditRepositoryProvider).deleteThing(c.fullname);
      _notifier.removeComment(c.fullname);
    } catch (e) {
      if (mounted) showActionError(context, 'delete', e);
    }
  }

  Future<void> _vote(Comment c, int dir) async {
    final current = dirOf(c.likes);
    final target = current == dir ? 0 : dir;
    // Upvoting comments says you're into this thread's subreddit.
    final p = _post;
    if (target == 1 && p != null) {
      ref.read(forYouLearnerProvider).commentUpvote(p);
    }
    _notifier.updateComment(
        c.fullname,
        (x) => x.copyWith(
            score: x.score + target - current, likes: likesOf(target)));
    final votes = ref.read(commentVotesProvider.notifier)..setVote(c, target);
    try {
      await ref.read(redditRepositoryProvider).vote(c.fullname, target);
    } catch (e) {
      _notifier.updateComment(
          c.fullname, (x) => x.copyWith(score: c.score, likes: c.likes));
      votes.setVote(c, current);
      if (mounted) showActionError(context, 'vote', e);
    }
  }

  Future<void> _toggleSave(Comment c) async {
    final next = !c.saved;
    _notifier.updateComment(c.fullname, (x) => x.copyWith(saved: next));
    try {
      await ref.read(redditRepositoryProvider).setSaved(c.fullname, next);
    } catch (e) {
      _notifier.updateComment(c.fullname, (x) => x.copyWith(saved: !next));
      if (mounted) showActionError(context, next ? 'save' : 'unsave', e);
    }
  }

  void _loadMore(Comment c) {
    final p = _post;
    if (p == null) return;
    // A "more" stub with no children ids is Reddit's "continue this thread":
    // the replies are too deep to fetch here, so open that branch in
    // single-comment focus mode.
    if (c.moreChildren.isEmpty && c.parentId.startsWith('t1_')) {
      context.push('/comments/${p.subreddit}/${p.id}'
          '?comment=${c.parentId.replaceFirst('t1_', '')}');
    } else {
      _notifier.loadMore(c);
    }
  }

  Future<void> _mod(Comment c, String doneMsg,
      Future<void> Function(dynamic repo) action) async {
    if (!await modAction(ScaffoldMessenger.of(context), ref, doneMsg, action)) {
      return;
    }
    if (doneMsg.startsWith('Distinguished')) {
      _notifier.updateComment(
          c.fullname, (x) => x.copyWith(distinguished: 'moderator'));
    } else if (doneMsg.startsWith('Undistinguished')) {
      _notifier.updateComment(
          c.fullname, (x) => x.copyWith(distinguished: null));
    }
  }

  /// The comment ⋯ menu's entries, in groups: share-ish actions, then yours
  /// (or block), then moderator actions.
  List<PopupMenuEntry<VoidCallback>> _menuItems(Comment c, bool isOwn,
      {bool withSave = false}) {
    MenuOption<VoidCallback> item(String label, VoidCallback f) =>
        MenuOption(f, label);
    final groups = <List<MenuOption<VoidCallback>>>[
      [
        if (withSave) item(c.saved ? 'Unsave' : 'Save', () => _toggleSave(c)),
        item('Copy text', () {
          Clipboard.setData(ClipboardData(text: c.body));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Copied')));
        }),
        if (c.permalink.isNotEmpty)
          item('Share',
              () => shareUrl(context, 'https://reddit.com${c.permalink}')),
        item('Share as image', () {
          final p = _post;
          if (p == null) return;
          showShareCommentImage(context,
              post: p, chain: CommentTree.chainTo(_flat, c));
        }),
      ],
      if (isOwn)
        [item('Edit', () => _edit(c)), item('Delete', () => _delete(c))]
      else if (c.author != '[deleted]')
        [
          item('Block u/${c.author}',
              () => confirmBlockUser(context, ref, c.author))
        ],
      // Moderators of this community (the post says so) can act on comments
      // too.
      if (_post?.canModPost == true)
        [
          item('Approve',
              () => _mod(c, 'Approved', (r) => r.modApprove(c.fullname))),
          item('Remove',
              () => _mod(c, 'Removed', (r) => r.modRemove(c.fullname))),
          item(
              'Remove as spam',
              () => _mod(c, 'Removed as spam',
                  (r) => r.modRemove(c.fullname, spam: true))),
          if (isOwn)
            c.distinguished == 'moderator'
                ? item(
                    'Undistinguish',
                    () => _mod(c, 'Undistinguished',
                        (r) => r.modDistinguish(c.fullname, how: 'no')))
                : item(
                    'Distinguish as mod',
                    () => _mod(c, 'Distinguished',
                        (r) => r.modDistinguish(c.fullname, how: 'yes'))),
        ],
    ];
    return menuGroups(groups);
  }

  /// What a swipe on a comment does, per Settings → Swipe actions.
  SwipeSpec? _swipe(SwipeAction action, Comment c) {
    final votes = Theme.of(context).extension<VoteColors>()!;
    final cs = Theme.of(context).colorScheme;
    return switch (action) {
      SwipeAction.upvote => SwipeSpec(action.icon, votes.up, () => _vote(c, 1)),
      SwipeAction.downvote =>
        SwipeSpec(action.icon, votes.down, () => _vote(c, -1)),
      SwipeAction.save =>
        SwipeSpec(action.icon, cs.primary, () => _toggleSave(c)),
      SwipeAction.reply =>
        SwipeSpec(action.icon, cs.tertiary, () => _reply(c)),
      SwipeAction.collapse => SwipeSpec(
          action.icon, cs.secondary, () => _notifier.toggleCollapse(c.id)),
      SwipeAction.hide ||
      SwipeAction.dismiss ||
      SwipeAction.hideSub ||
      SwipeAction.none =>
        null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentsControllerProvider(_key));
    final notifier = _notifier;
    final username =
        ref.watch(authControllerProvider).valueOrNull?.username ?? '';
    final settings = ref.watch(settingsControllerProvider);
    final thread = async.valueOrNull;
    _post = thread?.post;
    _dwellPost = thread?.post ?? widget.initialPost;
    _flat = thread?.flat ?? const [];
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
              itemBuilder: (_) => pickOneMenu([
                for (final s in commentSorts) (s, commentSortLabels[s] ?? s)
              ], notifier.sort),
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
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => showPostActionsSheet(context, ref, thread.post),
            ),
          if (thread != null &&
              username.isNotEmpty &&
              thread.post.author == username)
            PopupMenuButton<String>(
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Edit or delete',
              onSelected: (v) async {
                final post = thread.post;
                if (v == 'edit' && post.isSelf) {
                  final newText = await showEditSheet(context, ref,
                      thingFullname: post.fullname, initialText: post.selftext);
                  if (newText != null) notifier.applyEdit(post.fullname, newText);
                } else if (v == 'delete') {
                  if (!await _confirmDelete(context, 'post')) return;
                  try {
                    await ref
                        .read(redditRepositoryProvider)
                        .deleteThing(post.fullname);
                    if (context.mounted) Navigator.of(context).maybePop();
                  } catch (e) {
                    if (context.mounted) showActionError(context, 'delete', e);
                  }
                }
              },
              itemBuilder: (_) => menuGroups([
                [
                  if (thread.post.isSelf) const MenuOption('edit', 'Edit'),
                  const MenuOption('delete', 'Delete'),
                ],
              ]),
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
              onComment: _replyToPost,
              onSummarize: hasAiKey
                  ? () => showSummarySheet(context, ref, thread.post, _flat)
                  : null,
              onAsk: hasAiKey
                  ? () => showAskSheet(
                      context, ref, thread.post, _flat, _reveal)
                  : null,
              onNext: () => _jumpNext((c) => c.depth == 0),
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
                        onPressed: notifier.refresh,
                        child: const Text('Retry')),
                  ],
                ),
              ),
            ),
            data: (thread) {
              final list = RefreshBox(
                onRefresh: _refresh,
                child: _commentList(thread, username, settings),
              );
              if (widget.focusCommentId == null) return list;
              return Column(
                children: [
                  _FocusBanner(
                      onShowAll: () => context.replace(
                          '/comments/${widget.subreddit}/${widget.postId}')),
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

  Widget _commentList(PostThread thread, String username, Settings settings) {
    final flat = thread.flat;
    final calm = settings.postDisplay.isCalm;
    // Animated images in the thread pause while it scrolls.
    return ListScrolling(
        child: ScrollablePositionedList.builder(
      itemScrollController: _itemScroll,
      itemPositionsListener: _itemPositions,
      // Build comments about a screen ahead, so scrolling shows ready-made
      // rows instead of building them mid-frame.
      minCacheExtent: 900,
      padding: const EdgeInsets.only(top: 6, bottom: 96),
      itemCount: 1 + (flat.isEmpty ? 1 : flat.length),
      itemBuilder: (context, index) {
        if (index == 0) return _PostHeader(post: thread.post, fresh: true);
        if (flat.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: Text('No comments yet')),
          );
        }
        final i = index - 1;
        final c = flat[i];
        final highlighted = _currentMatchId == c.fullname;
        Widget row;
        if (c.isMore) {
          row = _MoreRow(
            comment: c,
            loading: thread.loadingMore.contains(c.fullname),
            onTap: () => _loadMore(c),
          );
        } else {
          final collapsed = thread.collapsed.contains(c.id);
          final isOwn = username.isNotEmpty && c.author == username;
          final row0 = _CommentRow(
            comment: c,
            calm: calm,
            highlighted: highlighted,
            isNew: _isNew(c, username),
            isOwn: isOwn,
            opAuthor: thread.post.author,
            collapsed: collapsed,
            tapToCollapse: settings.tapToCollapse,
            onToggle: () => _notifier.toggleCollapse(c.id),
            onVote: (dir) => _vote(c, dir),
            onReply: () => _reply(c),
            onToggleSave: () => _toggleSave(c),
            menuItems: () => _menuItems(c, isOwn, withSave: calm),
          );
          final folded =
              thread.collapsed.contains(CommentTree.folded(c.id)) && !collapsed;
          row = SwipeActions(
            enabled: settings.swipeActions,
            start: _swipe(settings.swipeCommentStart, c),
            end: _swipe(settings.swipeCommentEnd, c),
            child: folded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row0,
                      _FoldedReplies(
                          comment: c,
                          onTap: () => _notifier.unfold(c.id)),
                    ],
                  )
                : row0,
          );
        }
        if (!calm) return KeyedSubtree(key: ValueKey(c.fullname), child: row);
        // Calm: one container per top-level thread, drawn as contiguous rows
        // (still one list item per comment) whose first / last rows round the
        // container's top / bottom.
        return _CalmThreadRow(
          key: ValueKey(c.fullname),
          first: i == 0 || c.depth == 0,
          last: i == flat.length - 1 || flat[i + 1].depth == 0,
          highlighted: highlighted,
          child: row,
        );
      },
    ));
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

/// Single-comment view (from an inbox reply / permalink): "Show all" opens
/// the whole thread.
class _FocusBanner extends StatelessWidget {
  const _FocusBanner({required this.onShowAll});
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: InkWell(
        onTap: onShowAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      color: cs.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Show 12 replies" under a top-level comment opened folded (Settings →
/// Open threads collapsed).
class _FoldedReplies extends StatelessWidget {
  const _FoldedReplies({required this.comment, required this.onTap});
  final Comment comment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = CommentTree.replyCount(comment);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.unfold_more_rounded, size: 16),
        label: Text(n == 1 ? 'Show 1 reply' : 'Show $n replies'),
      ),
    );
  }
}

/// "Load more replies" node — a light indented row, not a card.
class _MoreRow extends StatelessWidget {
  const _MoreRow(
      {required this.comment, required this.loading, required this.onTap});
  final Comment comment;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final indent = comment.depth.clamp(0, 6) * 8.0;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(10 + indent, 0, 10, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: loading ? null : onTap,
          icon: loading
              ? const Loading.onContent()
              : Icon(Icons.add_circle_outline_rounded,
                  size: 18, color: cs.primary),
          label: Text(comment.moreChildren.isEmpty
              ? 'Continue thread →'
              : '${comment.moreCount} more replies'),
        ),
      ),
    );
  }
}

/// Inline previews for media linked in a comment or post body (images, gifs,
/// videos), so bodies don't just show a bare URL that opens a browser.
class _CommentMedia extends StatelessWidget {
  const _CommentMedia({required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final video = isVideoUrl(uri);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: GestureDetector(
        onTap: () => openLink(context, uri.toString()),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: video
                    ? Container(
                        height: 120,
                        width: double.infinity,
                        color: cs.surfaceContainerHighest,
                      )
                    : PauseWhileScrolling(
                        child: CachedNetworkImage(
                        imageUrl: uri.toString(),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        // A 120 placeholder only while loading; then the
                        // image's own height (max 260).
                        placeholder: (_, __) => Container(
                            height: 120, color: cs.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
                          height: 60,
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Text('Could not load media',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ),
                      )),
              ),
              if (video)
                Icon(Icons.play_circle_fill_rounded,
                    size: 48, color: cs.onSurface.withValues(alpha: .8)),
              if (isGifUrl(uri))
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }
}

/// A post / comment body in reading order: markdown text, with each image,
/// GIF or video drawn where it appears (a paragraph that's only a media link
/// shows as that media, not as the link).
class _BodyWithMedia extends StatelessWidget {
  const _BodyWithMedia({
    required this.body,
    required this.media,
    required this.maxMedia,
    this.selectable = false,
  });
  final String body;
  final Map<String, String> media;
  final int maxMedia;
  // Plain text in comments: a selectable paragraph is a full text editor
  // widget, far heavier to build while scrolling through hundreds of
  // comments (it also swallowed taps for tap-to-collapse). "Copy text" is
  // in the ⋯ menu.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final segments = bodySegments(body, media, maxMedia);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments)
          if (seg.media != null)
            _CommentMedia(uri: seg.media!)
          else
            RedditMarkdown(
              data: seg.markdown!,
              selectable: selectable,
              styleSheet: redditMarkdownStyle(context),
            ),
      ],
    );
  }
}

/// Runs a delete confirmation: "Delete [what]? This cannot be undone."
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
/// [↑ N new ↓] [your comment] [summarize] [ask] [comment] [● next top-level].
class _ThreadToolbar extends StatelessWidget {
  const _ThreadToolbar({
    required this.newCount,
    required this.hasMine,
    required this.hasComments,
    required this.onPrevNew,
    required this.onNextNew,
    required this.onMine,
    required this.onComment,
    this.onSummarize,
    this.onAsk,
    required this.onNext,
    required this.onNextLongPress,
  });

  final int newCount;
  final bool hasMine;
  final bool hasComments;
  final VoidCallback onPrevNew, onNextNew, onMine, onComment, onNext;
  final VoidCallback? onSummarize, onAsk; // only when AI is set up
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
            if (onSummarize != null)
              icon(Icons.auto_awesome_rounded, 'Summarize thread', onSummarize!),
            if (onAsk != null)
              icon(Icons.forum_rounded, 'Ask about this thread', onAsk!),
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
          child: Center(child: Loading()),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Post header
// ---------------------------------------------------------------------------

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
  // Calm: icon + membership from the subreddit's about (fetched once the
  // thread is in; the feed's copy shown while loading skips it).
  Subreddit? _about;
  bool? _joinedOverride;

  @override
  void initState() {
    super.initState();
    _sync();
    _fetchAbout();
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

  Future<void> _fetchAbout() async {
    if (!widget.fresh || widget.post.subreddit.isEmpty) return;
    if (!ref.read(settingsControllerProvider).postDisplay.isCalm) return;
    try {
      final about = await ref
          .read(redditRepositoryProvider)
          .getSubredditAbout(widget.post.subreddit);
      if (mounted) setState(() => _about = about);
    } catch (_) {}
  }

  Future<void> _vote(int dir) async {
    final overrides = ref.read(postOverridesProvider.notifier);
    final cur = overrides.effective(widget.post);
    final current = dirOf(cur.likes);
    final target = current == dir ? 0 : dir;
    overrides.setVote(widget.post, target);
    // Same learning as a vote on the card.
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

  Future<void> _toggleSave() async {
    final p = widget.post;
    final overrides = ref.read(postOverridesProvider.notifier);
    final next = !overrides.effective(p).saved;
    overrides.setSaved(p, next);
    final learner = ref.read(forYouLearnerProvider)..save(p, next);
    if (next) {
      offerReminder(context, p);
    } else {
      ref.read(postRemindersProvider.notifier).cancel(p.id);
    }
    try {
      await ref.read(redditRepositoryProvider).setSaved(p.fullname, next);
    } catch (e) {
      overrides.setSaved(p, !next);
      learner.save(p, !next);
      if (mounted) showActionError(context, next ? 'save' : 'unsave', e);
    }
  }

  Future<void> _toggleJoin(bool joined) async {
    final next = !joined;
    setState(() => _joinedOverride = next);
    try {
      await ref
          .read(redditRepositoryProvider)
          .setSubscribed(widget.post.subreddit, next);
    } catch (e) {
      if (mounted) setState(() => _joinedOverride = !next);
      if (mounted) showActionError(context, next ? 'join' : 'leave', e);
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
    final ov = ref.watch(postOverridesProvider.select((m) => m[p.id]));
    final likes = ov != null ? ov.likes : p.likes;
    final score = ov?.score ?? p.score;
    final saved = ov?.saved ?? p.saved;
    final numComments = ov?.numComments ?? p.numComments;
    if (ref.watch(
        settingsControllerProvider.select((s) => s.postDisplay.isCalm))) {
      return _calm(context, likes, score, saved, numComments);
    }
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
          Row(children: [
            Flexible(
              child: GestureDetector(
                onTap: () => context.push('/u/${p.author}'),
                child: Text('u/${p.author} · ${timeAgo(p.created)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            ),
            if (p.authorFlair != null) ...[
              const SizedBox(width: 6),
              Flexible(child: _FlairChip(flair: p.authorFlair!)),
            ],
          ]),
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
          CrosspostLine(post: p),
          ReminderLine(post: p),
          const SizedBox(height: 12),
          _media(cs, 16),
          PollOptions(post: p),
          // Gallery/image/link posts can carry a body too — show it whenever
          // there's selftext, not only for pure self-posts.
          if (p.selftext.isNotEmpty)
            _BodyWithMedia(
                body: p.selftext,
                media: p.bodyMedia,
                maxMedia: 10,
                selectable: true),
          const SizedBox(height: 12),
          Row(
            children: [
              _VotePill(
                  score: score,
                  likes: likes,
                  onUp: () => _vote(1),
                  onDown: () => _vote(-1)),
              const SizedBox(width: 8),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: ShapeDecoration(
                    shape: StadiumBorder(
                        side: BorderSide(color: cs.outlineVariant))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mode_comment_outlined,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(compactNumber(numComments),
                      style: Theme.of(context).textTheme.labelLarge),
                ]),
              ),
              const Spacer(),
              ToggleIcon(
                checked: saved,
                onChanged: (_) => _toggleSave(),
                on: Icons.bookmark_rounded,
                off: Icons.bookmark_border_rounded,
                description: 'Save',
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  /// The Calm post header: subreddit avatar + [r/sub / u/author · age] + a
  /// Join pill, a 24 regular title, the flair pill, media (radius 22) and
  /// the connected vote group, then the comment count.
  Widget _calm(BuildContext context, bool? likes, int score, bool saved,
      int numComments) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    final votes = Theme.of(context).extension<VoteColors>()!;
    final signedIn =
        (ref.watch(authControllerProvider).valueOrNull?.username ?? '')
            .isNotEmpty;
    final joined = _joinedOverride ?? _about?.userIsSubscriber;
    final up = likes == true, down = likes == false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: () => context.push('/r/${p.subreddit}'),
              child: LetterAvatar(
                name: p.subreddit,
                size: 40,
                container: cs.secondaryContainer,
                content: cs.onSecondaryContainer,
                imageUrl: _about?.iconUrl,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => context.push('/r/${p.subreddit}'),
                    child: Text(
                        p.subredditPrefixed.isEmpty
                            ? 'r/${p.subreddit}'
                            : p.subredditPrefixed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  Row(children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () => context.push('/u/${p.author}'),
                        child: Text('u/${p.author} · ${timeAgo(p.created)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ),
                    ),
                    if (p.authorFlair != null) ...[
                      const SizedBox(width: 6),
                      Flexible(child: _FlairChip(flair: p.authorFlair!)),
                    ],
                  ]),
                ],
              ),
            ),
            if (signedIn && joined != null) ...[
              const SizedBox(width: 8),
              Material(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _toggleJoin(joined),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    child: Text(joined ? 'Joined' : 'Join',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSecondaryContainer)),
                  ),
                ),
              ),
            ],
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(p.title,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    letterSpacing: -0.24)),
          ),
          if (p.linkFlairText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CalmFlair(raw: p.linkFlairText!),
            ),
          CrosspostLine(post: p),
          ReminderLine(post: p),
          const SizedBox(height: 12),
          _media(cs, 22),
          PollOptions(post: p),
          if (p.selftext.isNotEmpty)
            _BodyWithMedia(
                body: p.selftext,
                media: p.bodyMedia,
                maxMedia: 10,
                selectable: true),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              CalmButtonGroup(buttons: [
                CalmButton(
                  icon: Icons.arrow_upward_rounded,
                  label: compactNumber(score),
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
              ]),
              const SizedBox(width: 8),
              CalmButtonGroup(buttons: [
                CalmButton(
                    icon: Icons.mode_comment_outlined,
                    label: compactNumber(numComments),
                    onTap: () {}),
              ]),
              const Spacer(),
              CalmGhost(
                icon: Icons.share_rounded,
                label: 'Share',
                color: cs.onSurfaceVariant,
                onTap: () {
                  ref.read(forYouLearnerProvider).share(p);
                  shareUrl(context, 'https://reddit.com${p.permalink}',
                      subject: p.title);
                },
              ),
              CalmGhost(
                icon: saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: saved ? 'Unsave' : 'Save',
                color: saved ? cs.primary : cs.onSurfaceVariant,
                onTap: _toggleSave,
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 10),
            child: Text('${compactNumber(numComments)} comments',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _media(ColorScheme cs, double radius) {
    final p = widget.post;
    if (p.type == PostType.self) return const SizedBox.shrink();
    final blur =
        (p.over18 && ref.watch(settingsControllerProvider).blurNsfw) ||
            p.spoiler;
    final label = p.over18 ? 'NSFW' : 'Spoiler';
    if (p.type == PostType.gallery && p.gallery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NsfwBlur(
          blur: blur,
          label: label,
          child: p.gallery.length > 1
              ? GalleryM3Carousel(images: p.gallery, title: p.title)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: GalleryCarousel(images: p.gallery, title: p.title)),
        ),
      );
    }
    if (p.type == PostType.link) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: _openMedia,
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
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
        label: label,
        blurredImageUrl: p.blurredPreviewUrl,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
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

// ---------------------------------------------------------------------------
// Comments
// ---------------------------------------------------------------------------

/// Depth-edge colors (rotate by nesting level).
const _railColors = [
  Color(0xFF9F8BE8),
  Color(0xFF62B5AA),
  Color(0xFFE0A55C),
  Color(0xFFD88FB4),
  Color(0xFF7E9BE0),
];

/// One comment, in the classic card or as a Calm thread row. Vote and save
/// state live in the comment tree, not here.
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.calm,
    required this.highlighted,
    required this.isNew,
    required this.isOwn,
    required this.opAuthor,
    required this.collapsed,
    required this.tapToCollapse,
    required this.onToggle,
    required this.onVote,
    required this.onReply,
    required this.onToggleSave,
    required this.menuItems,
  });

  final Comment comment;
  final bool calm;
  final bool highlighted; // current in-post search match
  final bool isNew; // posted since the user's last visit to this thread
  final bool isOwn;
  final String opAuthor;
  final bool collapsed;
  final bool tapToCollapse;
  final VoidCallback onToggle;
  final void Function(int dir) onVote;
  final VoidCallback onReply;
  final VoidCallback onToggleSave;
  final List<PopupMenuEntry<VoidCallback>> Function() menuItems;

  @override
  Widget build(BuildContext context) =>
      calm ? _calmRow(context) : _card(context);

  Color _nameColor(ColorScheme cs) => comment.distinguished == 'moderator'
      ? const Color(0xFF4CAF50)
      : (isOwn ? cs.primary : cs.onSurface);

  /// Avatar + name (opens the profile), OP / PINNED badges, flair, age, NEW;
  /// [trailing] at the end.
  Widget _header(BuildContext context,
      {required double avatar,
      required String name,
      required FontWeight weight,
      required double ageSize,
      required Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    final c = comment;
    return Row(
      children: [
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: c.author == '[deleted]'
                ? null
                : () => context.push('/u/${c.author}'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AuthorDot(name: c.author, size: avatar),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: weight,
                          color: _nameColor(cs))),
                ),
              ],
            ),
          ),
        ),
        if (c.author == opAuthor && c.author != '[deleted]') ...[
          const SizedBox(width: 6),
          _Badge('OP', cs.primaryContainer, cs.onPrimaryContainer, 10),
        ],
        if (c.stickied) ...[
          const SizedBox(width: 6),
          _Badge('PINNED', cs.secondaryContainer, cs.onSecondaryContainer, 10),
        ],
        if (c.authorFlair != null) ...[
          const SizedBox(width: 6),
          Flexible(child: _FlairChip(flair: c.authorFlair!)),
        ],
        SizedBox(width: calm ? 6 : 8),
        Text('· ${timeAgo(c.created)}',
            maxLines: 1,
            style: TextStyle(fontSize: ageSize, color: cs.onSurfaceVariant)),
        if (isNew) ...[
          const SizedBox(width: 6),
          _Badge('NEW', cs.tertiaryContainer, cs.onTertiaryContainer, 10.5),
        ],
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _collapsedText(ColorScheme cs, EdgeInsets padding) => Padding(
        padding: padding,
        child: Text(
          comment.body.replaceAll('\n', ' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic),
        ),
      );

  Widget _body() => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: tapToCollapse ? onToggle : null,
        child: _BodyWithMedia(
            body: comment.body, media: comment.media, maxMedia: 3),
      );

  Widget _menuButton(ColorScheme cs, double size) =>
      PopupMenuButton<VoidCallback>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz_rounded,
            size: size, color: cs.onSurfaceVariant),
        onSelected: (f) => f(),
        itemBuilder: (_) => menuItems(),
      );

  /// The classic comment card.
  Widget _card(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final depth = comment.depth;
    final indent = depth.clamp(0, 6) * 8.0;
    final edge = _railColors[(depth - 1).clamp(0, _railColors.length - 1)];
    return Container(
      margin: EdgeInsetsDirectional.fromSTEB(10 + indent, 0, 10, 8),
      decoration: BoxDecoration(
        color: highlighted ? cs.primaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border:
            highlighted ? Border.all(color: cs.primary, width: 1.5) : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // A Stack, not IntrinsicHeight + Row: stretching the depth bar to the
      // comment's height cost a second layout pass for every comment.
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(start: depth > 0 ? 4 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Long-press collapses the whole subtree; tap re-expands a
                // collapsed comment (so a tap can't accidentally collapse)
                // unless tap-to-collapse is on.
                InkWell(
                  onTap: collapsed || tapToCollapse ? onToggle : null,
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    onToggle();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: _header(context,
                        avatar: 20,
                        name: 'u/${comment.author}',
                        weight: FontWeight.w700,
                        ageSize: 12.5,
                        trailing: collapsed
                            ? Icon(Icons.unfold_more_rounded,
                                size: 16, color: cs.onSurfaceVariant)
                            : null),
                  ),
                ),
                if (!collapsed) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _body(),
                  ),
                  _cardActions(context),
                ] else
                  _collapsedText(cs, const EdgeInsets.fromLTRB(40, 0, 12, 8)),
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
    );
  }

  Widget _cardActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final votes = Theme.of(context).extension<VoteColors>()!;
    final up = comment.likes == true;
    final down = comment.likes == false;
    Widget small(IconData icon, String tip, Color color, VoidCallback f) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: f,
          icon: Icon(icon, color: color),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          small(Icons.arrow_upward_rounded, 'Upvote',
              up ? votes.up : cs.onSurfaceVariant, () => onVote(1)),
          Text(comment.scoreHidden ? '–' : compactNumber(comment.score),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: up
                      ? votes.up
                      : (down ? votes.down : cs.onSurfaceVariant))),
          small(Icons.arrow_downward_rounded, 'Downvote',
              down ? votes.down : cs.onSurfaceVariant, () => onVote(-1)),
          TextButton.icon(
            onPressed: onReply,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.reply_rounded, size: 16),
            label: const Text('Reply', style: TextStyle(fontSize: 12.5)),
          ),
          const Spacer(),
          small(Icons.unfold_less_rounded, 'Collapse thread',
              cs.onSurfaceVariant, onToggle),
          small(
              comment.saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              comment.saved ? 'Unsave' : 'Save',
              comment.saved ? cs.primary : cs.onSurfaceVariant,
              onToggleSave),
          _menuButton(cs, 18),
        ],
      ),
    );
  }

  /// A Calm comment row inside its thread container: 2px neutral rails per
  /// depth (OP's own rail tinted primary), avatar 24 + name + OP + age, the
  /// body, and a small ↑ score ↓ · Reply · Collapse · ⋯ row (save in ⋯).
  Widget _calmRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final votes = Theme.of(context).extension<VoteColors>()!;
    final depth = comment.depth.clamp(0, 8);
    final isOp = comment.author == opAuthor && comment.author != '[deleted]';
    final up = comment.likes == true;
    final down = comment.likes == false;
    final muted = cs.onSurfaceVariant;
    Widget round(IconData icon, String tip, Color color, VoidCallback f) =>
        SizedBox(
          width: 32,
          height: 32,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: f,
            child: Icon(icon, size: 16, color: color, semanticLabel: tip),
          ),
        );
    return CustomPaint(
      // Rails: painted, not laid out (no extra layout pass per depth).
      painter: _RailsPainter(
        depth: depth,
        rail: cs.outlineVariant,
        opRail: isOp ? cs.primary.withValues(alpha: 0.55) : null,
        rtl: Directionality.of(context) == TextDirection.rtl,
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16 + depth * 10.0, 10, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: collapsed || tapToCollapse ? onToggle : null,
              onLongPress: () {
                HapticFeedback.selectionClick();
                onToggle();
              },
              child: _header(context,
                  avatar: 24,
                  name: comment.author,
                  weight: FontWeight.w500,
                  ageSize: 13,
                  trailing: collapsed
                      ? _CollapsePill(
                          icon: Icons.unfold_more_rounded,
                          label: 'Expand',
                          onTap: onToggle)
                      : null),
            ),
            if (collapsed)
              _collapsedText(cs, const EdgeInsets.only(top: 4))
            else ...[
              Padding(padding: const EdgeInsets.only(top: 4), child: _body()),
              // ↑ score ↓ · Reply · Collapse · ⋯ — small, 32 targets.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  round(Icons.arrow_upward_rounded, 'Upvote',
                      up ? votes.up : muted, () => onVote(1)),
                  Text(
                      comment.scoreHidden
                          ? '–'
                          : compactNumber(comment.score),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: up ? votes.up : (down ? votes.down : muted))),
                  round(Icons.arrow_downward_rounded, 'Downvote',
                      down ? votes.down : muted, () => onVote(-1)),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onReply,
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.reply_rounded, size: 16, color: muted),
                        const SizedBox(width: 4),
                        Text('Reply',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: muted)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  if (comment.saved)
                    Icon(Icons.bookmark_rounded,
                        size: 16, color: cs.primary, semanticLabel: 'Saved'),
                  _CollapsePill(
                      icon: Icons.unfold_less_rounded,
                      label: 'Collapse',
                      onTap: onToggle),
                  SizedBox(width: 32, height: 32, child: _menuButton(cs, 16)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A Calm comment's depth rails: 2 wide, 10 apart, from the row's top
/// inset to just above its bottom.
class _RailsPainter extends CustomPainter {
  _RailsPainter(
      {required this.depth,
      required this.rail,
      required this.opRail,
      required this.rtl});
  final int depth;
  final Color rail;
  final Color? opRail; // the OP's own rail (the innermost one)
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 2.0, top = 10.0;
    final bottom = size.height - 2;
    if (bottom <= top) return;
    for (var l = 0; l < depth; l++) {
      final x = 16 + l * 10 + 4.0;
      final color = (opRail != null && l == depth - 1) ? opRail! : rail;
      canvas.drawRect(
          Rect.fromLTWH(rtl ? size.width - x - w : x, top, w, bottom - top),
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_RailsPainter old) =>
      old.depth != depth ||
      old.rail != rail ||
      old.opRail != opRail ||
      old.rtl != rtl;
}

/// One row of a Calm thread container (radius 24, 12 side margin): [first]
/// rounds the top and adds the container's top inset, [last] rounds the
/// bottom and leaves the 10 gap to the next thread.
class _CalmThreadRow extends StatelessWidget {
  const _CalmThreadRow({
    super.key,
    required this.first,
    required this.last,
    required this.highlighted,
    required this.child,
  });
  final bool first;
  final bool last;
  final bool highlighted;
  final Widget child;

  static const _radius = Radius.circular(24);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, last ? 10 : 0),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: first ? _radius : Radius.zero,
          bottom: last ? _radius : Radius.zero,
        ),
        child: ColoredBox(
          color: calmCardColor(context),
          child: Padding(
            padding: EdgeInsets.only(top: first ? 6 : 0, bottom: last ? 6 : 0),
            child: highlighted
                ? ColoredBox(color: cs.primaryContainer, child: child)
                : child,
          ),
        ),
      ),
    );
  }
}

/// Calm thread's collapse / expand control: a labelled tonal pill, easy to
/// spot and hit.
class _CollapsePill extends StatelessWidget {
  const _CollapsePill(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Material(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 28,
            padding: const EdgeInsetsDirectional.only(start: 8, end: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: cs.onSecondaryContainer),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSecondaryContainer)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg, this.size);
  final String text;
  final Color bg;
  final Color fg;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                fontSize: size, fontWeight: FontWeight.w800, color: fg)),
      );
}

/// A user's flair in this community, next to their name: its text, with
/// its emoji drawn inline.
class _FlairChip extends StatelessWidget {
  const _FlairChip({required this.flair});
  final UserFlair flair;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6)),
      child: Text.rich(
        TextSpan(children: [
          for (final p in flair.parts)
            if (p.emojiUrl != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: CachedNetworkImage(
                    imageUrl: p.emojiUrl!, width: 14, height: 14),
              )
            else
              TextSpan(text: p.text ?? ''),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
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
    final color = deleted
        ? Theme.of(context).colorScheme.outline
        : _palette[h % _palette.length];
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
            fontSize: size * 0.5,
            height: 1),
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
            tooltip: 'Upvote',
            onPressed: onUp,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(Icons.arrow_upward_rounded,
                color: up ? votes.up : cs.onSurfaceVariant),
          ),
          Text(compactNumber(score),
              style: TextStyle(fontWeight: FontWeight.w700, color: countColor)),
          IconButton(
            tooltip: 'Downvote',
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
