import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
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
        return 'This community is quarantined. Opt in on reddit.com to view it.';
      case 'gold_only':
        return 'This community is for premium members only.';
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
  if (lower.contains('429')) {
    return "You're going a bit fast — Reddit is rate-limiting. Try again shortly.";
  }
  if (lower.contains('500') || lower.contains('502') || lower.contains('503')) {
    return 'Reddit is having problems right now. Try again later.';
  }
  return s;
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
  });

  final Object? message;
  final VoidCallback? onRetry;
  final IconData icon;

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
            Text(friendlyError(message), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
