import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of Reddit's API rate-limit headers (per OAuth client), taken [at].
class RateLimit {
  RateLimit(
      {required this.remaining,
      required this.used,
      required this.resetSeconds,
      DateTime? at})
      : at = at ?? DateTime.now();
  final int remaining;
  final int used;
  final int resetSeconds;
  final DateTime at;

  int get total => remaining + used;

  /// Seconds until this window resets, counted from when it was read.
  int secondsLeft([DateTime? now]) {
    final left = resetSeconds -
        (now ?? DateTime.now()).difference(at).inMilliseconds ~/ 1000;
    return left < 0 ? 0 : left;
  }

  /// The last one Reddit sent, for error copy built outside the widget tree
  /// (`friendlyError`).
  static RateLimit? latest;
}

final rateLimitProvider = StateProvider<RateLimit?>((ref) => null);
