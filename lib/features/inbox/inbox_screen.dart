import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/open_link.dart';
import '../../core/widgets/connected_choice.dart';
import '../../core/widgets/error_view.dart';
import '../../models/inbox_item.dart';
import '../auth/auth_controller.dart';
import '../feed/swipe_actions.dart';
import '../home/account_tab.dart' show SignInPrompt;
import '../home/tab_menu.dart';
import '../home/tab_signals.dart';
import '../web/reddit_web_screen.dart';
import 'inbox_controller.dart';
import 'reddit_notifications.dart';

/// The Inbox pager key for Reddit's own notifications (website sign-in only).
const _redditTab = 'reddit';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authControllerProvider).valueOrNull?.anonymous ?? false) {
      return Scaffold(
        appBar: AppBar(
            toolbarHeight: 64,
            leading: SideBarScope.of(context) != null
                ? const SideBarButton()
                : null,
            automaticallyImplyLeading: false,
            title: const Text('Inbox')),
        body: const SignInPrompt(
            message: 'Sign in to see your messages, replies and mentions.'),
      );
    }
    // Signed in on the web: Reddit's own notifications (a tab) and Chat.
    final webSignIn = ref.watch(webSignInProvider);
    return _InboxTabs(key: ValueKey(webSignIn), webSignIn: webSignIn);
  }
}

class _InboxTabs extends ConsumerStatefulWidget {
  const _InboxTabs({super.key, required this.webSignIn});
  final bool webSignIn;

  @override
  ConsumerState<_InboxTabs> createState() => _InboxTabsState();
}

class _InboxTabsState extends ConsumerState<_InboxTabs>
    with SingleTickerProviderStateMixin {
  late final List<(String, String)> _tabs = [
    ...inboxTabs,
    if (widget.webSignIn) ('Reddit', _redditTab),
  ];
  late final TabController _tab =
      TabController(length: _tabs.length, vsync: this)..addListener(_onTab);
  int _index = 0;

  // Rebuilds only when the selected tab changes (the Mark all read button
  // and the Reddit tab's page depend on it).
  void _onTab() {
    if (_tab.index != _index) setState(() => _index = _tab.index);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final where = _tabs[_index].$2;
    return Scaffold(
      appBar: AppBar(
        // 64 tall, as Kotlin's top app bar: the ☰ sits 8px from the top,
        // where the other tabs put it.
        toolbarHeight: 64,
        leading:
            SideBarScope.of(context) != null ? const SideBarButton() : null,
        automaticallyImplyLeading: false,
        title: const Text('Inbox'),
        actions: [
          if (widget.webSignIn)
            IconButton(
              tooltip: 'Reddit Chat',
              icon: const Icon(Icons.chat_outlined),
              onPressed: () =>
                  context.push(RedditWeb.route(RedditWeb.chat, 'Chat')),
            ),
          // Reddit's notifications are read-only here: nothing to mark.
          if (where != _redditTab)
            IconButton(
              tooltip: 'Mark all read',
              icon: const Icon(Icons.mark_email_read_outlined),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(inboxControllerProvider(where).notifier)
                      .markAllRead();
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                      content:
                          Text("Couldn't mark all read: ${friendlyError(e)}")));
                }
              },
            ),
          const SettingsButton(),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _tabs) Tab(text: t.$1)],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/compose_message'),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New message'),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _tabs[i].$2 == _redditTab
                ? _RedditNotificationsList(selected: _index == i)
                : _InboxList(where: _tabs[i].$2),
        ],
      ),
    );
  }
}

class _InboxList extends ConsumerStatefulWidget {
  const _InboxList({required this.where});
  final String where;

  @override
  ConsumerState<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends ConsumerState<_InboxList>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();

  // Kind filter, only used on the "All" tab: all | replies | mentions | messages.
  String _kindFilter = 'all';

  static const _kindFilters = [
    ('all', 'All'),
    ('replies', 'Replies'),
    ('mentions', 'Mentions'),
    ('messages', 'Messages'),
  ];

  @override
  bool get wantKeepAlive => true;

  List<InboxItem> _applyFilter(List<InboxItem> items) {
    if (widget.where != 'inbox' || _kindFilter == 'all') return items;
    return items.where((i) {
      switch (_kindFilter) {
        case 'replies':
          return i.kind == InboxKind.commentReply ||
              i.kind == InboxKind.postReply;
        case 'mentions':
          return i.kind == InboxKind.mention;
        case 'messages':
          return i.kind == InboxKind.message;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        ref.read(inboxControllerProvider(widget.where).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Re-tapping the Inbox tab scrolls the current list to top.
    ref.listen<int>(tabReselectProvider(2), (_, __) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
      }
    });
    final async = ref.watch(inboxControllerProvider(widget.where));
    final notifier = ref.read(inboxControllerProvider(widget.where).notifier);

    final body = RefreshIndicator(
      onRefresh: notifier.refresh,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('Could not load inbox.\n${friendlyError(e)}')),
          ),
        ]),
        data: (state) {
          final items = _applyFilter(state.items);
          // A kind filter can leave too few rows to scroll (or none, and no
          // list): keep fetching, within a bound, until there's a screenful.
          if (items.length < 10 &&
              state.hasMore &&
              !state.loadingMore &&
              state.items.length < 500) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => notifier.loadMore());
          }
          if (items.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('Nothing here')),
            ]);
          }
          return ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 130),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == items.length) {
                return state.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()))
                    : const SizedBox.shrink();
              }
              final item = items[i];
              return _SwipeableInboxCard(
                key: ValueKey(item.fullname),
                item: item,
                notifier: notifier,
                onOpen: () => _open(context, item),
              );
            },
          );
        },
      ),
    );

    if (widget.where != 'inbox') return body;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ConnectedChoice<String>(
          options: _kindFilters,
          selected: _kindFilter,
          onSelect: (k) => setState(() => _kindFilter = k),
        ),
      ),
      Expanded(child: body),
    ]);
  }

  void _open(BuildContext context, InboxItem item) {
    if (item.isNew) {
      ref.read(inboxControllerProvider(widget.where).notifier)
          .markRead(item.fullname);
    }
    if (item.isMessage) {
      context.push('/message', extra: item);
    } else {
      final ref0 = item.postRef;
      if (ref0 != null) {
        // Comment replies/mentions are t1_<id> → jump straight to that comment.
        final commentId = item.fullname.startsWith('t1_')
            ? item.fullname.substring(3)
            : null;
        final suffix = commentId != null ? '?comment=$commentId' : '';
        context.push('/comments/${ref0.subreddit}/${ref0.postId}$suffix');
      }
    }
  }
}

/// Messages: swipe right = read/unread, swipe left = delete.
/// Comment replies/mentions: read/unread only (they can't be deleted).
/// The feed's swipe (fires once on release, then springs back): a dismiss
/// row could stick half-way and fire repeatedly.
class _SwipeableInboxCard extends StatelessWidget {
  const _SwipeableInboxCard({
    super.key,
    required this.item,
    required this.notifier,
    required this.onOpen,
  });
  final InboxItem item;
  final InboxController notifier;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwipeActions(
      start: SwipeSpec(
        item.isNew
            ? Icons.mark_email_read_outlined
            : Icons.mark_email_unread_outlined,
        const Color(0xFF2E7D32),
        () => item.isNew
            ? notifier.markRead(item.fullname)
            : notifier.markUnread(item.fullname),
      ),
      end: item.isMessage
          ? SwipeSpec(Icons.delete_outline_rounded, cs.error,
              () => notifier.deleteMessage(item.fullname))
          : null,
      child: _InboxCard(item: item, onTap: onOpen),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.item, required this.onTap});
  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, label) = switch (item.kind) {
      InboxKind.message => (Icons.mail_outline_rounded, 'Message'),
      InboxKind.commentReply => (Icons.reply_rounded, 'Comment reply'),
      InboxKind.postReply => (Icons.forum_outlined, 'Post reply'),
      InboxKind.mention => (Icons.alternate_email_rounded, 'Mention'),
    };
    final heading = item.isMessage
        ? (item.subject.isEmpty ? '(no subject)' : item.subject)
        : (item.linkTitle ?? label);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('u/${item.author} · ${timeAgo(item.created)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                  if (item.isNew) _UnreadDot(color: cs.primary),
                ],
              ),
              const SizedBox(height: 8),
              Text(heading,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(item.body.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Reddit's own notifications (replies, mentions, upvote milestones…), read
/// from reddit.com when this tab is shown and kept a few minutes. A tap opens
/// the post or comment in Ilay; older ones are on reddit.com.
class _RedditNotificationsList extends ConsumerStatefulWidget {
  const _RedditNotificationsList({required this.selected});

  /// This page is the Inbox's current tab.
  final bool selected;

  @override
  ConsumerState<_RedditNotificationsList> createState() =>
      _RedditNotificationsListState();
}

class _RedditNotificationsListState
    extends ConsumerState<_RedditNotificationsList>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  late final RedditNotifications _notifs;
  bool? _active;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Kept for dispose, where ref can't be read.
    _notifs = ref.read(redditNotificationsProvider.notifier);
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        _notifs.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _notifs.release();
    super.dispose();
  }

  void _openWeb() => context.push(
      RedditWeb.route(redditNotificationsUrl, 'Reddit notifications'));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Only while you're on this tab (the pager also builds its neighbour,
    // and the Inbox stays alive under other tabs and screens); leaving it
    // lets the hidden page close.
    final active = widget.selected &&
        TickerMode.valuesOf(context).enabled &&
        ref.watch(homeTabProvider.select((t) => t == 2));
    if (active != _active) {
      _active = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _active != active) return;
        active ? _notifs.refresh() : _notifs.release();
      });
    }
    ref.listen<int>(tabReselectProvider(2), (_, __) {
      if (widget.selected && _scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
      }
    });
    final state = ref.watch(redditNotificationsProvider);

    final Widget child;
    switch (state) {
      case null:
      case RedditNotifLoading():
        child = const Center(child: CircularProgressIndicator());
      case RedditNotifFailed(:final signedOut):
        child = ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Text(
                  signedOut
                      ? 'Your Reddit website sign-in has expired. Sign in '
                          "again to see Reddit's notifications."
                      : "Couldn't load Reddit's notifications. Pull to try "
                          'again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _openWeb,
                    child: const Text('Open on reddit.com')),
              ],
            ),
          ),
        ]);
      case RedditNotifData(:final items, :final loadingMore, :final hasMore):
        final footer = loadingMore || (!hasMore && items.isNotEmpty);
        child = items.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('No notifications')),
              ])
            : ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 130),
                itemCount: items.length + (footer ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == items.length) {
                    return loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()))
                        : Center(
                            child: TextButton(
                                onPressed: _openWeb,
                                child: const Text(
                                    'Older notifications on reddit.com')));
                  }
                  final n = items[i];
                  return _RedditNotificationCard(
                    key: ValueKey(n.id),
                    n: n,
                    onTap: () {
                      _notifs.opened(n);
                      n.link != null ? openLink(context, n.link) : _openWeb();
                    },
                  );
                },
              );
    }
    return RefreshIndicator(
      onRefresh: () => _notifs.refresh(force: true),
      child: child,
    );
  }
}

class _RedditNotificationCard extends StatelessWidget {
  const _RedditNotificationCard(
      {super.key, required this.n, required this.onTap});
  final RedditNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, label) = n.type == 'POST_REPLY'
        ? (Icons.forum_outlined, 'Post reply')
        : n.type == 'COMMENT_REPLY'
            ? (Icons.reply_rounded, 'Comment reply')
            : n.type.contains('MENTION')
                ? (Icons.alternate_email_rounded, 'Mention')
                : n.type.startsWith('UPVOTE')
                    ? (Icons.arrow_upward_rounded, 'Upvotes')
                    : (Icons.notifications_outlined, 'Reddit');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                  if (n.at > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                        timeAgo(DateTime.fromMillisecondsSinceEpoch(n.at,
                            isUtc: true)),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                  const Spacer(),
                  if (n.unread) _UnreadDot(color: cs.primary),
                ],
              ),
              const SizedBox(height: 8),
              Text(n.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (n.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(n.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
