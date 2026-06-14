import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/inbox_item.dart';
import '../../models/listing.dart';

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

  InboxState copyWith({
    List<InboxItem>? items,
    String? after,
    bool? loadingMore,
  }) =>
      InboxState(
        items: items ?? this.items,
        after: after,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

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

  /// Optimistically marks one item read locally and on the server.
  Future<void> markRead(String fullname) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(items: [
        for (final i in current.items)
          i.fullname == fullname ? i.copyWith(isNew: false) : i,
      ]));
    }
    try {
      await ref.read(redditRepositoryProvider).markRead(fullname);
      ref.invalidate(unreadCountProvider);
    } catch (_) {/* keep optimistic state */}
  }

  /// Optimistically marks one item unread locally and on the server.
  Future<void> markUnread(String fullname) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(items: [
        for (final i in current.items)
          i.fullname == fullname ? i.copyWith(isNew: true) : i,
      ]));
    }
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

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
          items: [for (final i in current.items) i.copyWith(isNew: false)]));
    }
    await ref.read(redditRepositoryProvider).markAllRead();
    ref.invalidate(unreadCountProvider);
  }
}

final inboxControllerProvider =
    AsyncNotifierProviderFamily<InboxController, InboxState, String>(
        InboxController.new);

/// Unread message count for the bottom-nav badge.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(redditRepositoryProvider).getUnreadCount();
});
