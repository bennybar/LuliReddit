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
  // post as a <shreddit-post id="t3_…">; ads are separate elements.
  static const _readIds = '''
(function () {
  return Array.from(document.querySelectorAll('shreddit-post'))
    .filter(function (e) { return !e.hasAttribute('promoted'); })
    .map(function (e) { return e.getAttribute('id') || ''; })
    .filter(function (id) { return id.indexOf('t3_') === 0; });
})();
''';

  HeadlessInAppWebView? _view;
  InAppWebViewController? _page;
  final _seen = <String>{};

  /// The next [want] post ids. [restart] reloads Home from the top (first
  /// page / refresh) using [cookieHeader], the active account's session.
  Future<List<String>> next({
    required bool restart,
    required String cookieHeader,
    int want = 25,
  }) async {
    if (restart || _page == null) {
      await dispose();
      _seen.clear();
      await _open(cookieHeader);
    }
    final fresh = <String>[];
    var stalled = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (fresh.length < want && DateTime.now().isBefore(deadline)) {
      final before = fresh.length;
      for (final id in await _ids()) {
        if (_seen.add(id)) fresh.add(id);
      }
      if (fresh.length >= want) break;
      // The site fills in its feed a few seconds after the page loads, so
      // nothing found yet means "still loading" (up to the deadline), not
      // "end of feed". Only a feed that has shown posts can run out.
      if (fresh.length == before && _seen.isNotEmpty && ++stalled >= 5) {
        break; // end of feed
      }
      // Scroll to the bottom so the page loads its next batch, at a human pace.
      await _page!.evaluateJavascript(
          source: 'window.scrollTo(0, document.body.scrollHeight);');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return fresh;
  }

  Future<void> _open(String cookieHeader) async {
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
    final loaded = Completer<void>();
    _view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: _home),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
      onWebViewCreated: (c) => _page = c,
      onLoadStop: (_, __) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await _view!.run();
    await loaded.future.timeout(const Duration(seconds: 20));
  }

  Future<List<String>> _ids() async {
    final r = await _page?.evaluateJavascript(source: _readIds);
    return r is List ? [for (final v in r) '$v'] : const [];
  }

  Future<void> dispose() async {
    final v = _view;
    _view = null;
    _page = null;
    await v?.dispose();
  }
}

/// A one-off message for the feed (e.g. "Reddit Home couldn't load, showing
/// For You"), shown as a snackbar and then cleared.
final redditHomeNoticeProvider = StateProvider<String?>((ref) => null);
