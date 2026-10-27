import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reddit_repository.dart';
import '../features/auth/auth_controller.dart';
import '../features/settings/settings_controller.dart';
import 'network/rate_limit.dart';
import 'network/reddit_client.dart';

final redditClientProvider = Provider<RedditClient>((ref) {
  final client = RedditClient(
    ref.watch(secureStoreProvider),
    ref.watch(authRepositoryProvider),
    onRateLimit: (rl) => ref.read(rateLimitProvider.notifier).state = rl,
    cacheEnabled: () => ref.read(settingsControllerProvider).offlineCache,
  );
  // Re-read auth mode (OAuth vs website session) on any login / account switch.
  ref.listen(authControllerProvider, (_, __) => client.invalidateAuthConfig());
  return client;
});

final redditRepositoryProvider = Provider<RedditRepository>((ref) {
  final repo = RedditRepository(ref.watch(redditClientProvider));
  void apply(Settings s) {
    repo.subsCacheEnabled = s.subsCacheEnabled;
    repo.subsCacheTtl = Duration(minutes: s.subsCacheMinutes);
  }

  apply(ref.read(settingsControllerProvider));
  ref.listen(settingsControllerProvider, (_, s) => apply(s));
  return repo;
});
