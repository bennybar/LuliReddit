import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the user's real reddit.com Home feed — Reddit's own ranking and
/// recommendations — by loading the site in a hidden WebView with the user's
/// own website session, the way their browser would, and collecting the ids
/// of the posts the page shows, in order. Promoted posts are skipped.
///
/// EXPERIMENTAL and opt-in (Settings → Reddit Home): this is not an official
/// API. It uses no Reddit app credentials and doesn't disguise itself — it is
/// a browser view of the user's own Home — but automated reading of the site
/// is against Reddit's User Agreement, and it breaks whenever Reddit changes
/// its page. Callers fall back to For You when it yields nothing.
class RedditHomeLoader {
  static final _home = WebUri('https://www.reddit.com/');

  // The ids of the feed's posts, in page order. Reddit's site renders each
  // post as a <shreddit-post id="t3_…">; ads are separate elements. Returns
  // null while the previous document is still showing during a reload.
  static const _readIds = '''
(function () {
  if (document.documentElement.getAttribute('data-ilay-old')) return null;
  return Array.from(document.querySelectorAll('shreddit-post'))
    .filter(function (e) { return !e.hasAttribute('promoted'); })
    .map(function (e) { return e.getAttribute('id') || ''; })
    .filter(function (id) { return id.indexOf('t3_') === 0; });
})();
''';

  HeadlessInAppWebView? _view;
  InAppWebViewController? _page;
  String? _cookies; // the session the hidden browser was opened with
  final _seen = <String>{};

  /// The next post ids: on a [restart] (first page / refresh) the first ~10
  /// as soon as they render, otherwise up to [want] more. [cookieHeader] is
  /// the active account's session.
  Future<List<String>> next({
    required bool restart,
    required String cookieHeader,
    int want = 25,
    void Function(int found)? onProgress, // running count, for the UI
  }) async {
    if (_page == null || cookieHeader != _cookies) {
      // First use, or the account changed: (re)open with its session.
      await dispose();
      _seen.clear();
      await _open(cookieHeader);
    } else if (restart) {
      // Refresh: reload the page in the already-open browser instead of
      // tearing it down and re-setting every cookie. Mark the old document so
      // its posts aren't read as the new page's.
      _seen.clear();
      await _page!.evaluateJavascript(
          source: "document.documentElement.setAttribute('data-ilay-old','1')");
      await _page!.loadUrl(urlRequest: URLRequest(url: _home));
    }

    // A refresh hands back the first posts as soon as they render; the feed
    // pages for more on its own as you scroll.
    final target = restart ? 10 : want;
    final fresh = <String>[];
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var lastGrowth = DateTime.now();
    var lastScroll = DateTime.fromMillisecondsSinceEpoch(0);
    while (DateTime.now().isBefore(deadline)) {
      final ids = await _ids();
      var grew = false;
      for (final id in ids ?? const <String>[]) {
        if (_seen.add(id)) {
          fresh.add(id);
          grew = true;
        }
      }
      if (grew) onProgress?.call(fresh.length);
      if (fresh.length >= target) break;
      final now = DateTime.now();
      if (grew) lastGrowth = now;
      // Nothing new for a while after posts had appeared: end of the feed.
      // (Before any appear, the page is still loading — keep waiting.)
      if (_seen.isNotEmpty && now.difference(lastGrowth).inSeconds >= 6) break;
      // Out of rendered posts: scroll so the page loads its next batch, at
      // most every 1.5s.
      if (ids != null &&
          _seen.isNotEmpty &&
          !grew &&
          now.difference(lastScroll).inMilliseconds >= 1500) {
        lastScroll = now;
        await _page!.evaluateJavascript(
            source: 'window.scrollTo(0, document.body.scrollHeight);');
      }
      // Check often: posts appear well before the whole page has loaded.
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return fresh;
  }

  Future<void> _open(String cookieHeader) async {
    _cookies = cookieHeader;
    // The WebView's cookie jar may hold a different account's session (the
    // last one that signed in through it): load the active one's.
    final jar = CookieManager.instance();
    await jar.deleteCookies(url: _home, domain: '.reddit.com');
    for (final part in cookieHeader.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      await jar.setCookie(
        url: _home,
        name: part.substring(0, i).trim(),
        value: part.substring(i + 1).trim(),
        domain: '.reddit.com',
        isSecure: true,
      );
    }
    final created = Completer<void>();
    _view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: _home),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        // Ilay loads its own images for the cards; the hidden page doesn't
        // need to download any, which gets its posts on screen sooner.
        blockNetworkImage: true,
      ),
      onWebViewCreated: (c) {
        _page = c;
        if (!created.isCompleted) created.complete();
      },
    );
    await _view!.run();
    // Don't wait for the whole page to load: next() reads posts as soon as
    // they're in the page.
    await created.future.timeout(const Duration(seconds: 10));
  }

  /// The post ids on the page now, or null while a reload is still showing
  /// the previous page.
  Future<List<String>?> _ids() async {
    try {
      final r = await _page?.evaluateJavascript(source: _readIds);
      return r is List ? [for (final v in r) '$v'] : (r == null ? null : const []);
    } catch (_) {
      return const []; // page between documents
    }
  }

  Future<void> dispose() async {
    final v = _view;
    _view = null;
    _page = null;
    _cookies = null;
    await v?.dispose();
  }
}

/// A one-off message for the feed (e.g. "Reddit Home couldn't load, showing
/// For You"), shown as a snackbar and then cleared.
final redditHomeNoticeProvider = StateProvider<String?>((ref) => null);
