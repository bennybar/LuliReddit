import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../network/rate_limit.dart';
import '../network/reddit_client.dart';

/// Turns raw exceptions into friendly, human copy.
String friendlyError(Object? e) {
  if (e is RedditApiException) {
    switch (e.reason) {
      case 'private':
        return 'This community is private.';
      case 'banned':
        return 'This community has been banned by Reddit.';
      case 'quarantined':
        return 'This community is quarantined: it may have shocking or highly '
            'offensive content.';
      case 'gated':
        return 'This community may have sensitive content, such as mature '
            'themes or graphic images.';
      case 'gold_only':
        return 'This community is for premium members only.';
    }
    switch (e.statusCode) {
      case 403:
        return "You don't have permission to do that.";
      case 404:
        return 'Not found — it may have been removed.';
      case 429:
        return rateLimited();
    }
    if (e.statusCode >= 500 && e.statusCode <= 599) {
      return 'Reddit is having problems right now. Try again later.';
    }
  }
  final s = '$e'.replaceFirst('Exception: ', '');
  final lower = s.toLowerCase();
  if (lower.contains('socket') ||
      lower.contains('connection') ||
      lower.contains('failed host lookup')) {
    return 'You appear to be offline. Check your connection and try again.';
  }
  if (lower.contains('403')) return "You don't have permission to do that.";
  if (lower.contains('404')) return 'Not found — it may have been removed.';
  if (lower.contains('429')) return rateLimited();
  if (lower.contains('500') || lower.contains('502') || lower.contains('503')) {
    return 'Reddit is having problems right now. Try again later.';
  }
  return s;
}

/// Rate-limited: when Reddit said the window resets, say how long to wait.
String rateLimited([DateTime? now]) {
  final left = RateLimit.latest?.secondsLeft(now) ?? 0;
  if (left <= 0) {
    return "You're going a bit fast — Reddit is rate-limiting. Try again shortly.";
  }
  if (left < 60) {
    return 'Reddit is rate-limiting for a moment. Try again in ${left}s.';
  }
  return 'Reddit is rate-limiting. Try again in about '
      '${(left + 59) ~/ 60} min.';
}

/// Tells the user a quick action (vote, save, subscribe…) didn't go through,
/// after its optimistic UI was rolled back.
void showActionError(BuildContext context, String action, Object error) {
  if (!context.mounted) return;
  final anonymous = ProviderScope.containerOf(context, listen: false)
          .read(authControllerProvider)
          .valueOrNull
          ?.anonymous ??
      false;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(anonymous
          ? 'Sign in to $action — you\'re browsing without an account.'
          : "Couldn't $action: ${friendlyError(error)}")));
}

/// Consistent empty / error state with an optional retry.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
    this.retryLabel = 'Retry',
  });

  final Object? message;
  final VoidCallback? onRetry;
  final IconData icon;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message is String ? message as String : friendlyError(message),
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
