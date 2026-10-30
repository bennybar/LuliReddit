import 'package:dio/dio.dart';

import 'reddit_constants.dart';

/// Maps a reddit.com / redd.it URL to an in-app route, or null if unsupported.
String? routeForRedditUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  // Short links: redd.it/<postId>
  if (host == 'redd.it') {
    return segs.isNotEmpty ? '/comments/_/${segs.first}' : null;
  }
  if (!(host == 'reddit.com' || host.endsWith('.reddit.com'))) return null;

  // Comment / post permalinks: /r/<sub>/comments/<id>/<slug>/<commentId> or
  // /comments/<id>. A segment after the title slug is a focused comment.
  final ci = segs.indexOf('comments');
  if (ci != -1 && ci + 1 < segs.length) {
    final id = segs[ci + 1];
    final sub = (ci >= 2 && segs[ci - 2] == 'r') ? segs[ci - 1] : '_';
    final commentId = segs.length > ci + 3 ? segs[ci + 3] : null;
    final suffix = commentId != null ? '?comment=$commentId' : '';
    return '/comments/$sub/$id$suffix';
  }

  // Gallery: /gallery/<id> is the post itself.
  if (segs.length >= 2 && segs[0] == 'gallery') {
    return '/comments/_/${segs[1]}';
  }
  // A share link must be resolved first (resolveShareLink): /r/<sub>/s/<code>
  // is a post, not the subreddit; /u/<name>/s/<code> a custom feed, not the
  // user.
  if (segs.length >= 4 &&
      (segs[0] == 'r' || segs[0] == 'u' || segs[0] == 'user') &&
      segs[2] == 's') {
    return null;
  }

  // Multireddit: /user/<name>/m/<multi>
  if (segs.length >= 4 &&
      (segs[0] == 'user' || segs[0] == 'u') &&
      segs[2] == 'm') {
    return '/m/${segs[1]}/${segs[3]}';
  }

  // User: /u/<name> or /user/<name>
  if (segs.length >= 2 && (segs[0] == 'u' || segs[0] == 'user')) {
    return '/u/${segs[1]}';
  }

  // Subreddit: /r/<sub>
  if (segs.length >= 2 && segs[0] == 'r') return '/r/${segs[1]}';

  return null;
}

/// A link shared to Ilay from another app by the iOS share extension,
/// `luli://share?url=<reddit link>[&summarize=1]`: the link, and whether
/// "Summarize with Ilay" (rather than "Open in Ilay") was picked.
({Uri url, bool summarize})? sharedLink(Uri uri) {
  if (uri.scheme != 'luli' || uri.host != 'share') return null;
  final url = Uri.tryParse(uri.queryParameters['url'] ?? '');
  if (url == null || !_isRedditHost(url.host)) return null;
  return (url: url, summarize: uri.queryParameters['summarize'] == '1');
}

/// The post id in a [routeForRedditUrl] post route (`/comments/<sub>/<id>`).
String? postIdInRoute(String route) =>
    RegExp(r'^/comments/[^/]+/([^/?]+)').firstMatch(route)?.group(1);

/// A post shared to "Summarize with Ilay": its summary opens once the thread
/// loads.
String? summarizeOnOpen;

bool _isRedditHost(String host) {
  final h = host.toLowerCase();
  return h == 'redd.it' ||
      h.endsWith('.redd.it') ||
      h == 'reddit.com' ||
      h.endsWith('.reddit.com');
}

/// A share link (`reddit.com/r/<sub>/s/<code>`, or `/u/<name>/s/<code>` for
/// a custom feed): it only redirects to the real post / comment / feed URL.
bool isShareLink(Uri uri) {
  if (!_isRedditHost(uri.host)) return false;
  final s = uri.pathSegments.where((x) => x.isNotEmpty).toList();
  return s.length >= 4 &&
      (s[0] == 'r' || s[0] == 'u' || s[0] == 'user') &&
      s[2] == 's';
}

/// Follows a [isShareLink] URL's redirects (up to 3) to the link it stands
/// for; null if it can't.
Future<Uri?> resolveShareLink(Uri uri) async {
  final dio = Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (_) => true,
    headers: {'User-Agent': RedditConstants.webUserAgent},
  ));
  var url = uri.toString();
  Future<String?> location(bool head) async {
    try {
      final res = head ? await dio.head<void>(url) : await dio.get<void>(url);
      return res.headers.value('location');
    } catch (_) {
      return null;
    }
  }

  for (var i = 0; i < 3; i++) {
    // HEAD first (no body); some servers only redirect a GET.
    final next = await location(true) ?? await location(false);
    if (next == null) return null;
    final target = next.startsWith('/') ? 'https://www.reddit.com$next' : next;
    final u = Uri.tryParse(target);
    if (u == null) return null;
    if (!isShareLink(u)) return u;
    url = target;
  }
  return null;
}
