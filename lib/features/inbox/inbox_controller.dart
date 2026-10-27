import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/inbox_item.dart';
import '../../models/listing.dart';
import '../auth/auth_controller.dart';
import 'reddit_notifications.dart';

/// The Inbox tabs: (label, where).
const inboxTabs = [
  ('All', 'inbox'),
  ('Unread', 'unread'),
  ('Messages', 'messages'),
  ('Sent', 'sent'),
];

/// Whether [fullname] is unread in any loaded tab (null if it isn't loaded).
bool? _isNewAnywhere(Ref ref, String fullname) {
  for (final (_, where) in inboxTabs) {
    if (!ref.exists(inboxControllerProvider(where))) continue;
    final items = ref.read(inboxControllerProvider(where)).valueOrNull?.items;
    for (final i in items ?? const <InboxItem>[]) {
      if (i.fullname == fullname) return i.isNew;
    }
  }
  return null;
}

/// Replies / mentions (comment ids) Reddit's notification list says you
/// opened elsewhere: mark the loaded unread ones read here and in Reddit's
/// inbox (not back on the notification list, where they already are).
void markInboxReadFromReddit(Ref ref, List<String> commentIds) {
  // Any loaded tab's controller marks it in all of them.
  final loaded = inboxTabs
      .where((t) => ref.exists(inboxControllerProvider(t.$2)))
      .firstOrNull;
  if (loaded == null) return;
  final inbox = ref.read(inboxControllerProvider(loaded.$2).notifier);
  for (final id in commentIds) {
    final fullname = 't1_$id';
    if (_isNewAnywhere(ref, fullname) == true) {
      inbox.markRead(fullname, notifications: false);
    }
  }
}

class InboxState {
  const InboxState({
    required this.items,
    this.after,
    this.loadingMore = false,
  });
  final List<InboxItem> items;
  final String? after;
  final bool loadingMore;

  bool get hasMore => after != null && after!.isNotEmpty;

  // [after] keeps its value when not passed (null is a real value: no more
  // pages), so updating items doesn't lose the tab's paging.
  InboxState copyWith({
    List<InboxItem>? items,
    Object? after = _keep,
    bool? loadingMore,
  }) =>
      InboxState(
        items: items ?? this.items,
        after: identical(after, _keep) ? this.after : after as String?,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

const _keep = Object();

/// arg = where (inbox | unread | messages | sent)
class InboxController extends FamilyAsyncNotifier<InboxState, String> {
  @override
  Future<InboxState> build(String arg) async {
    final listing =
        await ref.read(redditRepositoryProvider).getInbox(where: arg);
    return InboxState(items: listing.items, after: listing.after);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => build(arg));
    ref.invalidate(unreadCountProvider);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, after: current.after));
    try {
      final Listing<InboxItem> listing = await ref
          .read(redditRepositoryProvider)
          .getInbox(where: arg, after: current.after);
      state = AsyncData(current.copyWith(
        items: [...current.items, ...listing.items],
        after: listing.after,
        loadingMore: false,
      ));
    } catch (_) {
      state =
          AsyncData(current.copyWith(loadingMore: false, after: current.after));
    }
  }

  // Sets [fullname]'s read flag in this tab's loaded list.
  void _setNew(String fullname, bool isNew) {
    final current = state.valueOrNull;
    if (current == null ||
        !current.items.any((i) => i.fullname == fullname)) {
      return;
    }
    state = AsyncData(current.copyWith(
      after: current.after,
      items: [
        for (final i in current.items)
          i.fullname == fullname ? i.copyWith(isNew: isNew) : i,
      ],
    ));
  }

  // In every loaded tab (an item can show in several).
  void _setNewEverywhere(String fullname, bool isNew) {
    for (final (_, where) in inboxTabs) {
      if (ref.exists(inboxControllerProvider(where))) {
        ref
            .read(inboxControllerProvider(where).notifier)
            ._setNew(fullname, isNew);
      }
    }
  }

  /// Optimistically marks one item read locally and on the server
  /// ([notifications]: Reddit's notification list too).
  Future<void> markRead(String fullname, {bool notifications = true}) async {
    // Already read: nothing to send (a repeated swipe used to fire again and
    // again, hitting Reddit's rate limit).
    if (_isNewAnywhere(ref, fullname) == false) return;
    _setNewEverywhere(fullname, false);
    // Replies and mentions also sit in Reddit's notification list (website
    // sign-in).
    if (notifications && fullname.startsWith('t1_')) {
      ref
          .read(redditNotificationsProvider.notifier)
          .markReadOnReddit(fullname.substring(3));
    }
    try {
      await ref.read(redditRepositoryProvider).markRead(fullname);
      ref.invalidate(unreadCountProvider);
    } catch (_) {/* keep optimistic state */}
  }

  /// Optimistically marks one item unread locally and on the server.
  Future<void> markUnread(String fullname) async {
    if (_isNewAnywhere(ref, fullname) == true) return;
    _setNewEverywhere(fullname, true);
    try {
      await ref.read(redditRepositoryProvider).markUnread(fullname);
      ref.invalidate(unreadCountProvider);
    } catch (_) {/* keep optimistic state */}
  }

  /// Deletes a private message (t4_). Optimistically removes it from the list.
  Future<void> deleteMessage(String fullname) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
          items: [for (final i in current.items) if (i.fullname != fullname) i]));
    }
    try {
      await ref.read(redditRepositoryProvider).deleteMessage(fullname);
      ref.invalidate(unreadCountProvider);
    } catch (_) {/* keep optimistic removal */}
  }

  /// Marks *everything* read — Reddit's read_all_messages has no per-tab
  /// variant — so every tab is refreshed afterwards, not just this one.
  /// Throws on failure (after restoring this tab) so the caller can say so.
  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
          items: [for (final i in current.items) i.copyWith(isNew: false)]));
    }
    try {
      await ref.read(redditRepositoryProvider).markAllRead();
    } catch (_) {
      if (current != null) state = AsyncData(current);
      rethrow;
    }
    ref.read(redditNotificationsProvider.notifier).markAllReadOnReddit();
    ref.invalidate(inboxControllerProvider);
    ref.invalidate(unreadCountProvider);
  }
}

final inboxControllerProvider =
    AsyncNotifierProviderFamily<InboxController, InboxState, String>(
        InboxController.new);

/// Unread message count for the bottom-nav badge.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  // No inbox while browsing without an account.
  if (ref.watch(authControllerProvider).valueOrNull?.anonymous ?? false) {
    return 0;
  }
  return ref.watch(redditRepositoryProvider).getUnreadCount();
});
