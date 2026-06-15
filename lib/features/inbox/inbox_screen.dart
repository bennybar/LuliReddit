import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/inbox_item.dart';
import '../home/tab_signals.dart';
import 'inbox_controller.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  static const _tabs = [
    ('All', 'inbox'),
    ('Unread', 'unread'),
    ('Messages', 'messages'),
    ('Sent', 'sent'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inbox'),
          actions: [
            Builder(builder: (ctx) {
              return IconButton(
                tooltip: 'Mark this tab read',
                icon: const Icon(Icons.mark_email_read_outlined),
                onPressed: () {
                  final i = DefaultTabController.of(ctx).index;
                  ref
                      .read(inboxControllerProvider(_tabs[i].$2).notifier)
                      .markAllRead();
                },
              );
            }),
          ],
          bottom: TabBar(
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
          children: [for (final t in _tabs) _InboxList(where: t.$2)],
        ),
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

  Widget _filterBar() {
    const opts = [
      ('all', 'All'),
      ('replies', 'Replies'),
      ('mentions', 'Mentions'),
      ('messages', 'Messages'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (final o in opts) ...[
            ChoiceChip(
              label: Text(o.$2),
              selected: _kindFilter == o.$1,
              onSelected: (_) => setState(() => _kindFilter = o.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
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
            child: Center(child: Text('Could not load inbox.\n$e')),
          ),
        ]),
        data: (state) {
          final items = _applyFilter(state.items);
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
              return Dismissible(
                key: ValueKey(item.fullname),
                // Messages: swipe right = read/unread, swipe left = delete.
                // Comment replies/mentions: read/unread only (can't be deleted).
                direction: item.isMessage
                    ? DismissDirection.horizontal
                    : DismissDirection.startToEnd,
                background: _swipeBg(context, read: true, isNew: item.isNew),
                secondaryBackground: _swipeBg(context, read: false),
                confirmDismiss: (dir) async {
                  if (dir == DismissDirection.startToEnd) {
                    item.isNew
                        ? notifier.markRead(item.fullname)
                        : notifier.markUnread(item.fullname);
                    return false; // keep the row; we just toggled state
                  }
                  notifier.deleteMessage(item.fullname);
                  return true; // remove the row
                },
                child: _InboxCard(
                  item: item,
                  onTap: () => _open(context, ref, item),
                ),
              );
            },
          );
        },
      ),
    );

    if (widget.where != 'inbox') return body;
    return Column(children: [_filterBar(), Expanded(child: body)]);
  }

  /// [read]=true → the read/unread (right-swipe) background; else the delete
  /// (left-swipe) background.
  Widget _swipeBg(BuildContext context, {required bool read, bool isNew = false}) {
    if (read) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isNew
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined,
                color: Colors.white),
            const SizedBox(width: 8),
            Text(isNew ? 'Mark read' : 'Mark unread',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Delete',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          SizedBox(width: 8),
          Icon(Icons.delete_outline_rounded, color: Colors.white),
        ],
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, InboxItem item) {
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
                  if (item.isNew)
                    Container(
                      width: 9,
                      height: 9,
                      decoration:
                          BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    ),
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
