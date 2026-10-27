import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/network/web_session_cookies.dart';
import '../../models/post.dart';

/// The page shows the logged-out site: the website session has expired.
class HomeSignedOutException implements Exception {
  @override
  String toString() => 'Your Reddit website sign-in has expired';
}

/// One post as reddit.com's Home page shows it — enough for a feed card
/// straight away (the full post is fetched in the background).
class PagePost {
  const PagePost({
    required this.id,
    required this.title,
    required this.subreddit,
    this.subredditIcon,
    required this.author,
    required this.score,
    required this.comments,
    required this.created,
    required this.type,
    required this.permalink,
    required this.href,
    required this.domain,
    this.image,
    required this.body,
    this.flair,
    required this.nsfw,
    required this.spoiler,
    this.reason,
    required this.canShowFewer,
  });

  final String id; // t3_…
  final String title;
  final String subreddit;
  final String? subredditIcon;
  final String author;
  final int score;
  final int comments;
  final DateTime created;
  final String type; // text | image | video | gallery | link | crosspost | …
  final String permalink;
  final String href;
  final String domain;
  final String? image;
  final String body;
  final String? flair;
  final bool nsfw;
  final bool spoiler;

  /// Reddit's "why you're seeing this", when it shows one.
  final String? reason;

  /// Reddit offers "Show fewer posts like this" for it (recommended posts).
  final bool canShowFewer;

  /// A feed card's worth of [Post]: replaced by the full post once fetched.
  Post toPost() {
    final bare = id.replaceFirst('t3_', '');
    final sub = subreddit.replaceFirst('r/', '');
    final link = Uri.tryParse(href);
    final vreddit = link != null &&
            link.host == 'v.redd.it' &&
            link.pathSegments.isNotEmpty
        ? link.pathSegments.first
        : null;
    final postType = switch (type) {
      'text' => PostType.self,
      'image' => PostType.image,
      'gallery' => PostType.gallery,
      'video' => PostType.video,
      'link' => PostType.link,
      _ => image != null ? PostType.image : PostType.self,
    };
    return Post(
      id: bare,
      fullname: id,
      title: title,
      subreddit: sub,
      subredditPrefixed: 'r/$sub',
      subredditIcon: subredditIcon,
      author: author,
      score: score,
      numComments: comments,
      upvoteRatio: 0,
      created: created,
      permalink: permalink,
      url: href.isEmpty ? 'https://www.reddit.com$permalink' : href,
      domain: domain,
      type: postType,
      isSelf: postType == PostType.self,
      selftext: body,
      over18: nsfw,
      spoiler: spoiler,
      linkFlairText: flair,
      feedReason: reason,
      previewUrl: image,
      previewMedUrl: image,
      hlsUrl: vreddit == null
          ? null
          : 'https://v.redd.it/$vreddit/HLSPlaylist.m3u8',
    );
  }

  /// One post from the page's script, or null if it isn't a post.
  static PagePost? parse(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    String? nonEmpty(String k) => s(k).isEmpty ? null : s(k);
    final id = s('id');
    if (!id.startsWith('t3_')) return null;
    return PagePost(
      id: id,
      title: s('title').trim(),
      subreddit: s('sub'),
      subredditIcon: nonEmpty('subIcon'),
      author: s('author').isEmpty ? '[deleted]' : s('author'),
      score: int.tryParse(s('score')) ?? 0,
      comments: int.tryParse(s('comments')) ?? 0,
      created: DateTime.tryParse(s('created'))?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      type: s('type'),
      permalink: s('permalink'),
      href: s('href'),
      domain: s('domain'),
      image: nonEmpty('img'),
      body: s('body'),
      flair: nonEmpty('flair'),
      nsfw: raw['nsfw'] == true,
      spoiler: raw['spoiler'] == true,
      reason: nonEmpty('reason'),
      canShowFewer: raw['fewer'] == true,
    );
  }
}

/// What the page shows now: its posts, and whether it's the logged-out site.
class HomePageRead {
  const HomePageRead(this.posts, this.signedOut);
  final List<PagePost> posts;
  final bool signedOut;

  /// The page script's JSON result, or null while a reload is still showing
  /// the previous page.
  static HomePageRead? parse(Object? r) {
    if (r == null || r == 'null') return null;
    final json = r is String ? jsonDecode(r) : r;
    if (json is! Map) return null;
    return HomePageRead([
      for (final p in (json['posts'] as List?) ?? const [])
        if (PagePost.parse(p) case final post?) post
    ], json['signedOut'] == true);
  }
}

/// Reads the user's real reddit.com Home feed — Reddit's own ranking and
/// recommendations — by loading the site in a hidden WebView with the user's
/// own website session, the way their browser would, and reading the posts
/// the page shows, in order. Promoted posts are skipped.
///
/// EXPERIMENTAL and opt-in (Settings → Reddit Home): this is not an official
/// API. It uses no Reddit app credentials and doesn't disguise itself — it is
/// a browser view of the user's own Home — but automated reading of the site
/// is against Reddit's User Agreement, and it breaks whenever Reddit changes
/// its page. Callers fall back to For You when it yields nothing.
///
/// Every page call runs one at a time ([_locked]).
class RedditHomeLoader {
  static final _home = WebUri('https://www.reddit.com/');

  // The feed's posts, in page order, as cards: Reddit's site renders each
  // post as a <shreddit-post id="t3_…" post-title=… score=…> with its body
  // snippet, media preview and flair in named slots, and the recommendation
  // reason / "Show fewer" option on its ⋯ menu. Ads are separate elements.
  // signedOut: the page is the logged-out site (the session expired).
  // Returns null while the previous document is still showing during a
  // reload. (Element and attribute names as of 2026-10.)
  static const _readPosts = r'''
(function () {
  if (document.documentElement.getAttribute('data-ilay-old')) return null;
  var app = document.querySelector('shreddit-app');
  var signedOut = !!app && app.getAttribute('user-logged-in') !== 'true';
  var posts = Array.from(document.querySelectorAll('shreddit-post'))
    .filter(function (e) { return !e.hasAttribute('promoted') && (e.id || '').indexOf('t3_') === 0; })
    .map(function (e) {
      function slot(n) { return e.querySelector('[slot="' + n + '"]'); }
      var media = slot('post-media-container');
      var img = media && media.querySelector('img');
      var body = slot('text-body');
      var flair = slot('post-flair');
      var credit = slot('credit-bar');
      var subIcon = credit && credit.querySelector('img');
      var menu = e.querySelector('shreddit-post-overflow-menu');
      var reason = '', fewer = false;
      try {
        var rc = JSON.parse((menu && menu.getAttribute('recommendation-context-json')) || '{}');
        // Recommended (not from a subscription): Reddit offers "Show fewer" on these.
        fewer = !!(rc && rc.recommendationSource) && rc.recommendationSource.indexOf('subscribed') !== 0;
        if (rc && rc.content && !rc.isContextHidden) {
          var doc = JSON.parse(rc.content.richtext || '{}').document || [];
          reason = doc.map(function (p) { return (p.c || []).map(function (c) { return c.t || ''; }).join(''); }).join(' ').trim();
        }
      } catch (x) {}
      return {
        id: e.id, title: e.getAttribute('post-title') || '',
        sub: e.getAttribute('subreddit-prefixed-name') || '', author: e.getAttribute('author') || '',
        subIcon: subIcon ? (subIcon.getAttribute('src') || '') : '',
        score: e.getAttribute('score') || '0', comments: e.getAttribute('comment-count') || '0',
        created: e.getAttribute('created-timestamp') || '', type: e.getAttribute('post-type') || '',
        permalink: e.getAttribute('permalink') || '', href: e.getAttribute('content-href') || '',
        domain: e.getAttribute('domain') || '',
        img: img ? (img.getAttribute('src') || '') : '',
        body: body ? (body.innerText || '').trim().slice(0, 400) : '',
        flair: flair ? (flair.innerText || '').trim() : '',
        nsfw: e.hasAttribute('nsfw'), spoiler: e.hasAttribute('spoiler'),
        reason: reason, fewer: fewer
      };
    });
  return JSON.stringify({ signedOut: signedOut, posts: posts });
})();
''';

  /// Only downloads that never change what the feed shows: autoplaying video
  /// and fonts. Reddit's own events must go through — Home learns from them
  /// which posts were seen, and without them a refresh kept serving the same
  /// feed. (Content-blocker patterns are WebKit's regex subset: no `|`.)
  static final skippable = [
    r'^https?://v\.redd\.it/',
    r'^https?://packaged-media\.redd\.it/',
    r'^https?://fonts\.gstatic\.com/',
    for (final ext in ['mp4', 'm3u8', 'mpd', 'm4s', 'ts', 'woff', 'woff2', 'ttf', 'webm'])
      '\\.$ext([?#].*)?\$',
  ];

  HeadlessInAppWebView? _view;
  InAppWebViewController? _page;
  String? _cookies; // the session the hidden browser was opened with
  final _seen = <String>{};

  // One page call at a time; [cancel] makes the ones waiting or running give
  // up (what Kotlin does by cancelling their jobs).
  Future<void> _tail = Future.value();
  bool _busy = false;
  int _epoch = 0;

  /// Ids (bare) of the posts on the hidden page now that Reddit offers "Show
  /// fewer" for. Only those can take it: a card from an earlier page (one
  /// saved before the app was closed) isn't on this one.
  Set<String> showFewerIds = const {};

  Future<T> _locked<T>(Future<T> Function() f) {
    final run = _tail.then((_) async {
      _busy = true;
      try {
        return await f();
      } finally {
        _busy = false;
      }
    });
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Stops the reads waiting or running now (refresh, feed closed): they
  /// return what they have, so a new one doesn't wait behind them.
  void cancel() => _epoch++;

  /// The next posts: on a [restart] (first page / refresh) the first ~10 as
  /// soon as they render, otherwise up to [want] more. [cookieHeader] is the
  /// active account's session. Throws [HomeSignedOutException] when the page
  /// shows the logged-out site.
  Future<List<PagePost>> next({
    required bool restart,
    required String cookieHeader,
    int want = 25,
    void Function(int found)? onProgress, // running count, for the UI
  }) {
    final epoch = _epoch;
    return _locked(() async {
      if (epoch != _epoch) return const <PagePost>[];
      if (_page == null || cookieHeader != _cookies) {
        // First use, or the account changed: (re)open with its session.
        await _disposeNow();
        _seen.clear();
        await _open(cookieHeader);
      } else if (restart) {
        // Refresh: reload the page in the already-open browser instead of
        // tearing it down and re-setting every cookie. Mark the old document
        // so its posts aren't read as the new page's.
        _seen.clear();
        await _eval(
            "document.documentElement.setAttribute('data-ilay-old','1')");
        await _page?.loadUrl(urlRequest: URLRequest(url: _home));
      }

      // A refresh hands back the first posts as soon as they render; the
      // feed pages for more on its own as you scroll.
      final target = restart ? 10 : want;
      final fresh = <PagePost>[];
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var lastGrowth = DateTime.now();
      var lastScroll = DateTime.fromMillisecondsSinceEpoch(0);
      while (DateTime.now().isBefore(deadline) && epoch == _epoch) {
        final page = await _read();
        if (page?.signedOut ?? false) throw HomeSignedOutException();
        if (page != null) {
          showFewerIds = {
            for (final p in page.posts)
              if (p.canShowFewer) p.id.replaceFirst('t3_', '')
          };
        }
        var grew = false;
        for (final p in page?.posts ?? const <PagePost>[]) {
          if (_seen.add(p.id)) {
            fresh.add(p);
            grew = true;
          }
        }
        if (grew) onProgress?.call(fresh.length);
        if (fresh.length >= target) break;
        final now = DateTime.now();
        if (grew) lastGrowth = now;
        // Nothing new for a while after posts had appeared: end of the feed.
        // (Before any appear, the page is still loading — keep waiting.)
        // Once a batch has been flowing, a shorter quiet spell is enough.
        final quiet = fresh.isNotEmpty ? 4000 : 6000;
        if (_seen.isNotEmpty &&
            now.difference(lastGrowth).inMilliseconds >= quiet) {
          break;
        }
        // Out of rendered posts: scroll so the page loads its next batch, at
        // most every second.
        if (page != null &&
            _seen.isNotEmpty &&
            !grew &&
            now.difference(lastScroll).inMilliseconds >= 1000) {
          lastScroll = now;
          await _eval('window.scrollTo(0, document.body.scrollHeight);');
        }
        // Check often: posts appear well before the whole page has loaded.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return fresh;
    });
  }

  /// Scrolls the hidden page to [postId] (what the user is looking at in
  /// Ilay), so Reddit's own "seen" tracking follows what was actually on
  /// screen. Skipped while a page load is running.
  Future<void> scrollTo(String postId) async {
    if (_busy) return;
    await _locked(() => _eval("(function(){var e=document.getElementById("
        "'$postId');if(e)e.scrollIntoView({block:'center'});})()"));
  }

  /// Picks "Show fewer posts like this" in the post's own ⋯ menu on the
  /// hidden page — the same action as on reddit.com. False if it isn't
  /// offered there.
  Future<bool> showFewer(String postId) => _locked(() async {
        // The menu's items may only be rendered once it has been opened:
        // open it (off screen, in the hidden page) and look again.
        for (var attempt = 0; attempt < 4; attempt++) {
          final r = '${await _eval('''
(function(){
  var p = document.getElementById('$postId');
  var m = p && p.querySelector('shreddit-post-overflow-menu');
  if (!m) return 'gone';
  var li = m.shadowRoot && m.shadowRoot.querySelector('#post-overflow-showFewer');
  if (!li) {
    var b = (m.shadowRoot && m.shadowRoot.querySelector('button')) || m.querySelector('button');
    if (b && $attempt === 0) b.click();
    return 'none';
  }
  (li.querySelector('[role="menuitem"]') || li).click();
  return 'ok';
})()
''')}';
          if (r.contains('ok')) return true;
          if (r.contains('gone')) return false;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        return false;
      });

  /// The app went to the background: stop the hidden page's timers and
  /// media.
  Future<void> pause() async {
    final p = _page;
    if (p == null) return;
    try {
      await p.pauseTimers();
      await p.setAllMediaPlaybackSuspended(suspended: true);
    } catch (_) {/* page between documents */}
  }

  Future<void> resume() async {
    final p = _page;
    if (p == null) return;
    try {
      await p.resumeTimers();
      await p.setAllMediaPlaybackSuspended(suspended: false);
    } catch (_) {}
  }

  Future<void> _open(String cookieHeader) async {
    _cookies = cookieHeader;
    // The WebView's cookie jar may hold a different account's session (the
    // last one that signed in through it): load the active one's.
    await loadWebSessionCookies(cookieHeader);
    final created = Completer<void>();
    late final HeadlessInAppWebView v;
    v = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: _home),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        // Ilay loads its own images for the cards; the hidden page doesn't
        // need to download any, which gets its posts on screen sooner.
        blockNetworkImage: true,
        // Skip what the page doesn't need to list its posts: autoplaying
        // videos (dozens of streams) and fonts. Reddit's own scripts, checks
        // and events load.
        contentBlockers: [
          for (final filter in skippable)
            ContentBlocker(
              trigger: ContentBlockerTrigger(urlFilter: filter),
              action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
        ],
      ),
      onWebViewCreated: (c) {
        if (_view == v) _page = c;
        if (!created.isCompleted) created.complete();
      },
      // The page's content process died (crashed, or killed for memory):
      // drop this page, and the next Home load opens a new one.
      onWebContentProcessDidTerminate: (_) {
        if (_view != v) return;
        _view = null;
        _page = null;
        _cookies = null;
        v.dispose();
      },
    );
    _view = v;
    await v.run();
    // Don't wait for the whole page to load: next() reads posts as soon as
    // they're in the page.
    await created.future.timeout(const Duration(seconds: 10));
  }

  Future<Object?> _eval(String js) async {
    final p = _page;
    if (p == null) return null;
    // While the page is reloading, a script's result can be dropped
    // entirely; without a timeout that hung a refresh forever on "Opening
    // your Home…".
    try {
      return await p
          .evaluateJavascript(source: js)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      return null; // page between documents
    }
  }

  /// The posts on the page now, or null while a reload is still showing the
  /// previous page.
  Future<HomePageRead?> _read() async {
    try {
      return HomePageRead.parse(await _eval(_readPosts));
    } catch (_) {
      return const HomePageRead([], false); // page between documents
    }
  }

  Future<void> _disposeNow() async {
    final v = _view;
    _view = null;
    _page = null;
    _cookies = null;
    showFewerIds = const {};
    await v?.dispose();
  }

  Future<void> dispose() {
    cancel();
    return _locked(_disposeNow);
  }
}
