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

/// What the Home feed shows now (live, saved page, For You fallback); null
/// before the first load. Set by the Reddit Home engine and the feed.
final homeStatusProvider = StateProvider<HomeStatus?>((ref) => null);
