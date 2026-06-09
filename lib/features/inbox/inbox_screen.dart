import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/inbox_item.dart';
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
            IconButton(
              tooltip: 'Mark all read',
              icon: const Icon(Icons.mark_email_read_outlined),
              onPressed: () =>
                  ref.read(inboxControllerProvider('inbox').notifier).markAllRead(),
            ),
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

  @override
  bool get wantKeepAlive => true;

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
    final async = ref.watch(inboxControllerProvider(widget.where));
    final notifier = ref.read(inboxControllerProvider(widget.where).notifier);

    return RefreshIndicator(
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
          if (state.items.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('Nothing here')),
            ]);
          }
          return ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 130),
            itemCount: state.items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == state.items.length) {
                return state.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()))
                    : const SizedBox.shrink();
              }
              return _InboxCard(
                item: state.items[i],
                onTap: () => _open(context, ref, state.items[i]),
              );
            },
          );
        },
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
        context.push('/comments/${ref0.subreddit}/${ref0.postId}');
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
