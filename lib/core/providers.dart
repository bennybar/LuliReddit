import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reddit_repository.dart';
import '../features/auth/auth_controller.dart';
import '../features/settings/settings_controller.dart';
import 'network/rate_limit.dart';
import 'network/reddit_client.dart';

final redditClientProvider = Provider<RedditClient>((ref) {
  return RedditClient(
    ref.watch(secureStoreProvider),
    ref.watch(authRepositoryProvider),
    onRateLimit: (rl) => ref.read(rateLimitProvider.notifier).state = rl,
    cacheEnabled: () => ref.read(settingsControllerProvider).offlineCache,
  );
});

final redditRepositoryProvider = Provider<RedditRepository>(
  (ref) => RedditRepository(ref.watch(redditClientProvider)),
);
