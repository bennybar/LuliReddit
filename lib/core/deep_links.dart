/// Maps a reddit.com / redd.it URL to an in-app route, or null if unsupported.
String? routeForRedditUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  // Short links: redd.it/<postId>
  if (host == 'redd.it') {
    return segs.isNotEmpty ? '/comments/_/${segs.first}' : null;
  }
  if (!(host == 'reddit.com' || host.endsWith('.reddit.com'))) return null;

  // Comment / post permalinks: /r/<sub>/comments/<id>/...  or  /comments/<id>
  final ci = segs.indexOf('comments');
  if (ci != -1 && ci + 1 < segs.length) {
    final id = segs[ci + 1];
    final sub = (ci >= 2 && segs[ci - 2] == 'r') ? segs[ci - 1] : '_';
    return '/comments/$sub/$id';
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
