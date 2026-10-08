import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../explore/explore_screen.dart';
import '../feed/feed_controller.dart';
import '../feed/post_overrides.dart';
import '../inbox/inbox_controller.dart';
import '../multireddit/multireddit_providers.dart';

/// Drops everything that belongs to the previously active account — feeds,
/// inbox, subscriptions, custom feeds and local vote/save state — so the next
/// account never sees it. The on-disk response cache is keyed per account in
/// RedditClient, so it needs no clearing here.
void resetAccountScopedState(WidgetRef ref) {
  ref.read(redditRepositoryProvider).clearSubsCache();
  ref.invalidate(feedControllerProvider);
  ref.invalidate(inboxControllerProvider);
  ref.invalidate(unreadCountProvider);
  ref.invalidate(subscribedSubredditsProvider);
  ref.invalidate(myMultiredditsProvider);
  ref.invalidate(postOverridesProvider);
}
