import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of Reddit's API rate-limit headers (per OAuth client).
class RateLimit {
  const RateLimit({required this.remaining, required this.used, required this.resetSeconds});
  final int remaining;
  final int used;
  final int resetSeconds;

  int get total => remaining + used;
}

final rateLimitProvider = StateProvider<RateLimit?>((ref) => null);
