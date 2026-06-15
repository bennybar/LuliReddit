import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped when a bottom-nav tab is re-tapped while already active, so that tab's
/// scrollable can scroll to top. Keyed by tab index (1 = Explore, 2 = Inbox).
/// (The Posts tab uses its own `frontpageScrollSignalProvider`, which also
/// refreshes when already at the top.)
final tabReselectProvider = StateProvider.family<int, int>((ref, tab) => 0);
