import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/multireddit.dart';

final myMultiredditsProvider =
    FutureProvider.autoDispose<List<Multireddit>>((ref) {
  return ref.watch(redditRepositoryProvider).getMyMultireddits();
});

/// Looks up a single multireddit by name from the user's list.
final multiredditByNameProvider =
    FutureProvider.autoDispose.family<Multireddit?, String>((ref, name) async {
  final list = await ref.watch(redditRepositoryProvider).getMyMultireddits();
  for (final m in list) {
    if (m.name == name) return m;
  }
  return null;
});
