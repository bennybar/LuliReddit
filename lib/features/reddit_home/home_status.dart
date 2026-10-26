import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the Home feed is showing (a strip under its sort bar says so, unless
/// it's live).
sealed class HomeStatus {
  const HomeStatus();
}

/// Your live Reddit Home, loaded at [at].
class HomeLive extends HomeStatus {
  const HomeLive(this.at);
  final DateTime at;
}

/// The Home page saved at [at]: back after iOS closed Ilay, or Home couldn't
/// load.
class HomeSaved extends HomeStatus {
  const HomeSaved(this.at);
  final DateTime at;
}

/// For You instead, because Home couldn't load; [signedOut]: the website
/// sign-in expired.
class HomeFellBack extends HomeStatus {
  const HomeFellBack({required this.signedOut});
  final bool signedOut;
}

/// What the Home feed shows now; null before the first load.
// TODO(reddit-home): the Reddit Home area sets this from its loader (live,
// saved page, For You fallback) and drops the redditHomeNoticeProvider
// snackbar; until then it stays null and no strip shows.
final homeStatusProvider = StateProvider<HomeStatus?>((ref) => null);
