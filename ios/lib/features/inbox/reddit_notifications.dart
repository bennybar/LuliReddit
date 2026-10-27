import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/web_session_cookies.dart';
import '../../core/reddit_constants.dart';
import '../auth/auth_controller.dart';
import '../reddit_home/reddit_home_loader.dart';
import '../settings/settings_controller.dart' show sharedPrefsProvider;
import 'inbox_controller.dart';

/// One entry of Reddit's own notification list (reddit.com/notifications).
@immutable
class RedditNotification {
  const RedditNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.link,
    this.at = 0,
    this.avatar,
    this.clicked,
    this.unread = false,
  });

  final String id;

  /// Reddit's message type, e.g. POST_REPLY, COMMENT_REPLY, UPVOTE_POST,
  /// USERNAME_MENTION.
  final String type;
  final String title;
  final String body;

  /// Where it goes (a post or comment link), opened in Ilay.
  final String? link;

  /// Epoch millis (0: not known).
  final int at;
  final String? avatar;

  /// Reddit's "clicked" flag when the page shows it (null: not known).
  final bool? clicked;

  /// Not opened yet: new since you last looked or unread on Reddit, and not
  /// opened in Ilay.
  final bool unread;

  RedditNotification copyWith({bool? unread}) => RedditNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        link: link,
        at: at,
        avatar: avatar,
        clicked: clicked,
        unread: unread ?? this.unread,
      );
}

sealed class RedditNotifState {
  const RedditNotifState();
}

class RedditNotifLoading extends RedditNotifState {
  const RedditNotifLoading();
}

class RedditNotifData extends RedditNotifState {
  const RedditNotifData(this.items, this.at,
      {this.hasMore = false, this.loadingMore = false});
  final List<RedditNotification> items;
  final DateTime at;
  final bool hasMore;
  final bool loadingMore;

  RedditNotifData copyWith(
          {List<RedditNotification>? items,
          bool? hasMore,
          bool? loadingMore}) =>
      RedditNotifData(items ?? this.items, at,
          hasMore: hasMore ?? this.hasMore,
          loadingMore: loadingMore ?? this.loadingMore);
}

class RedditNotifFailed extends RedditNotifState {
  const RedditNotifFailed({required this.signedOut});
  final bool signedOut;
}

const redditNotificationsUrl = 'https://www.reddit.com/notifications';

/// The comment a notification link points at
/// (`.../comments/<post>/<slug>/<comment>/`), or null.
String? commentIdOf(String link) =>
    RegExp(r'/comments/[a-z0-9]+/[^/]+/([a-z0-9]+)/?(?:[?#].*)?$')
        .firstMatch(link)
        ?.group(1) ??
    RegExp(r'/comment/([a-z0-9]+)/?(?:[?#].*)?$').firstMatch(link)?.group(1);

/// The notifications in what the page script read ([_read]): drops entries
/// without an id or title, and repeats.
List<RedditNotification> parseRedditNotifications(Object? json) {
  final items = json is Map ? json['items'] : null;
  if (items is! List) return const [];
  final seen = <String>{};
  final out = <RedditNotification>[];
  String? str(Object? v) => v is String ? v : null;
  for (final e in items) {
    if (e is! Map) continue;
    final id = str(e['id']);
    final title = str(e['title']) ?? '';
    if (id == null || title.isEmpty || !seen.add(id)) continue;
    final link = str(e['link']);
    final avatar = str(e['avatar']);
    final ts = str(e['ts']);
    final clicked = e['clicked'];
    out.add(RedditNotification(
      id: id,
      type: str(e['type']) ?? '',
      title: title,
      body: str(e['body']) ?? '',
      link: link != null && link.startsWith('http') ? link : null,
      at: ts == null
          ? 0
          : DateTime.tryParse(ts)?.millisecondsSinceEpoch ?? 0,
      avatar: avatar != null && avatar.startsWith('http') ? avatar : null,
      clicked: clicked is bool ? clicked : null,
    ));
  }
  return out;
}

// Each <notification-item>: its link, title, body, time, avatar, and
// Reddit's clicked flag (in the tracking data of its ⋯ menu, once the page
// has drawn it); plus the link to the next, older batch. Defines ilayRead /
// ilayNext on the page for _fetchMore to reuse.
const _read = r'''(function(){
window.ilayRead=function(root){var out=[];
root.querySelectorAll('notification-item').forEach(function(e){
  var a=e.querySelector('a[href]');
  var t=e.querySelector('[data-testid=title]');
  var b=e.querySelector('[data-testid=body] > .line-clamp-2');
  var ts=e.querySelector('faceplate-timeago');
  var img=e.querySelector('img');
  var clicked=null;
  try{var m=e.querySelector('notification-context-menu');var tr=m&&m.shadowRoot&&m.shadowRoot.querySelector('faceplate-tracker');
    var ctx=tr&&JSON.parse(tr.getAttribute('data-faceplate-tracking-context'));if(ctx&&ctx.inbox&&typeof ctx.inbox.is_clicked==='boolean')clicked=ctx.inbox.is_clicked;}catch(x){}
  out.push({id:e.getAttribute('notification-id'),type:e.getAttribute('message-type'),
    link:a?a.href:null,title:t?t.textContent.trim():'',body:b?b.textContent.trim():'',
    ts:ts?ts.getAttribute('ts'):null,avatar:img?img.getAttribute('src'):null,clicked:clicked});
});return out;};
window.ilayNext=function(root){var p=root.querySelector('faceplate-partial[src*="notifications-inbox-content"]');return p?p.getAttribute('src'):null;};
return JSON.stringify({login:location.pathname.indexOf('/login')===0||location.hostname.indexOf('accounts.')===0,
  ready:!!document.querySelector('mark-all-messages-read,mark-all-notifications-seen'),items:ilayRead(document),next:ilayNext(document)});
})()''';

class _PageResult {
  const _PageResult(this.items, this.next,
      {required this.signedOut, required this.ok});
  final List<RedditNotification> items;
  final String? next;
  final bool signedOut;
  final bool ok;
}

/// Reddit's own notifications (website sign-in), shown natively in the Inbox.
/// Like Home, read from reddit.com in a hidden page. The page opens when you
/// go to the tab and closes soon after you leave it (or when the app goes to
/// the background); while open it also reads older notifications (one small
/// request a batch) and tells Reddit which one you opened. Kept a few
/// minutes, so coming back costs nothing; no background checks.
class RedditNotifications extends Notifier<RedditNotifState?> {
  static const _freshFor = Duration(minutes: 3);
  static const _timeout = Duration(seconds: 25);
  static const _maxIds = 400;
  static const _seenKey = 'redditNotifSeen';
  static const _openedKey = 'redditNotifOpened';

  String _user = '';

  // The hidden page and the link to the next batch.
  HeadlessInAppWebView? _view;
  InAppWebViewController? _page;
  String? _nextUrl;
  Timer? _closeTimer;

  // One page job at a time (Kotlin's Mutex).
  Future<void>? _tail;
  int _locks = 0;
  bool get _locked => _locks > 0;

  // In the background the page is closed and nothing new opens.
  bool _paused = false;
  // The tab is showing (it refreshes on coming back to the app).
  bool _active = false;

  // Inbox items marked read in Ilay, waiting to be marked on Reddit too.
  final _toMark = <String>{};
  bool _markAll = false;
  Timer? _markTimer;

  @override
  RedditNotifState? build() {
    _user = ref.watch(authControllerProvider
        .select((s) => s.valueOrNull?.username ?? ''));
    final lifecycle = AppLifecycleListener(
      onHide: () {
        _paused = true;
        _closeTimer?.cancel();
        _closeView(update: true);
      },
      onShow: () {
        _paused = false;
        if (_toMark.isNotEmpty || _markAll) _queueMark();
        if (_active) refresh();
      },
    );
    // A new account (or sign-out): its own list, and a fresh page.
    ref.onDispose(() {
      lifecycle.dispose();
      _closeTimer?.cancel();
      _markTimer?.cancel();
      _toMark.clear();
      _markAll = false;
      _closeView(update: false);
    });
    return null;
  }

  Future<T> _withLock<T>(Future<T> Function() f) async {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    _locks++;
    try {
      if (prev != null) await prev;
      return await f();
    } finally {
      _locks--;
      done.complete();
    }
  }

  /// Loads the list unless a recent copy is showing ([force]: pull to
  /// refresh).
  Future<void> refresh({bool force = false}) async {
    _active = true;
    _closeTimer?.cancel();
    final s = state;
    if (_locked || _paused) return;
    if (!force &&
        s is RedditNotifData &&
        DateTime.now().difference(s.at) < _freshFor) {
      return;
    }
    await _withLock(() async {
      final forUser = _user;
      if (state is! RedditNotifData) state = const RedditNotifLoading();
      _PageResult? result;
      try {
        final store = ref.read(secureStoreProvider);
        if (await store.authMode == 'web') {
          final cookie = await store.webCookie;
          if (cookie != null && cookie.isNotEmpty) result = await _open(cookie);
        }
      } catch (_) {
        result = const _PageResult([], null, signedOut: false, ok: false);
      }
      if (forUser != _user) return; // account changed meanwhile
      final cur = state;
      if (result == null) {
        state = const RedditNotifFailed(signedOut: true);
      } else if (result.ok) {
        _nextUrl = result.next;
        state = RedditNotifData(_mark(result.items), DateTime.now(),
            hasMore: result.next != null);
      } else if (cur is! RedditNotifData) {
        // A failed refresh keeps the list you had.
        state = RedditNotifFailed(signedOut: result.signedOut);
      }
    });
  }

  /// The next batch of older notifications, read through the open page.
  void loadMore() {
    final s = state;
    if (s is! RedditNotifData || !s.hasMore || s.loadingMore || _locked) {
      return;
    }
    state = s.copyWith(loadingMore: true);
    _withLock(() async {
      final url = _nextUrl;
      final more = url == null ? null : await _fetchMore(url);
      final cur = state;
      final known = cur is RedditNotifData
          ? {for (final n in cur.items) n.id}
          : const <String>{};
      final added = more == null
          ? const <RedditNotification>[]
          : _mark([
              for (final n in more.items)
                if (!known.contains(n.id)) n
            ]);
      _nextUrl = more?.next;
      final now = state;
      if (now is RedditNotifData) {
        state = now.copyWith(
            items: [...now.items, ...added],
            hasMore: more?.next != null && added.isNotEmpty,
            loadingMore: false);
      }
    });
  }

  /// You opened [n]: it stops showing as unread here, and the open page
  /// clicks it too, which is how Reddit learns it was opened (Reddit's page
  /// then moves to the post, so it steps back to the list).
  void opened(RedditNotification n) {
    _remember(_openedKey, [n.id]);
    _setRead({n.id});
    final p = _page;
    if (p != null) _clickItem(p, n.id);
  }

  void _setRead(Set<String> ids) {
    final s = state;
    if (s is! RedditNotifData) return;
    state = s.copyWith(items: [
      for (final it in s.items)
        ids.contains(it.id) ? it.copyWith(unread: false) : it
    ]);
  }

  /// A reply or mention (comment [commentId]) was read in Ilay's Inbox:
  /// Reddit's notification for it is a separate list, so mark it there too
  /// (website sign-in only). Batched: reads close together share one page
  /// load.
  void markReadOnReddit(String commentId) {
    _toMark.add(commentId);
    _queueMark();
  }

  /// Inbox → Mark all read: Reddit's "Mark all as read" on its notification
  /// list too.
  void markAllReadOnReddit() {
    _markAll = true;
    _queueMark();
  }

  void _queueMark() {
    _markTimer?.cancel();
    // In the background: sent on coming back (onShow).
    if (_paused) return;
    _markTimer = Timer(const Duration(seconds: 2), () async {
      await _withLock(() async {
        if (_paused) return; // kept for onShow
        final ids = _toMark.toList();
        final all = _markAll;
        _toMark.clear();
        _markAll = false;
        if (ids.isEmpty && !all) return;
        final store = ref.read(secureStoreProvider);
        if (await store.authMode != 'web') return;
        final cookie = await store.webCookie;
        if (cookie == null || cookie.isEmpty) return;
        _closeTimer?.cancel();
        if (_page == null) {
          try {
            final r = await _open(cookie);
            if (r.ok) {
              _nextUrl = r.next;
              state = RedditNotifData(_mark(r.items), DateTime.now(),
                  hasMore: r.next != null);
            }
          } catch (_) {
            return;
          }
        }
        final p = _page;
        if (p == null) return;
        if (all) {
          await _eval(
              p,
              "(function(){var b=document.querySelector("
              "'mark-all-messages-read button');if(b)b.click();"
              'return !!b})()');
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          final s = state;
          if (s is RedditNotifData) {
            state = s.copyWith(
                items: [for (final it in s.items) it.copyWith(unread: false)]);
          }
        } else {
          final opened = <String>[];
          for (final id in ids) {
            final s = state;
            if (s is! RedditNotifData) break;
            final n = s.items
                .where((it) => it.link?.contains('/$id/') ?? false)
                .firstOrNull;
            if (n == null) continue;
            opened.add(n.id);
            await _clickItem(p, n.id);
          }
          if (opened.isNotEmpty) {
            _remember(_openedKey, opened);
            _setRead(opened.toSet());
          }
        }
      });
      // Reading replies one after another: the next one reuses the page
      // (while the tab is showing, it stays).
      if (!_active) release(after: const Duration(seconds: 60));
    });
  }

  // Clicks one notification in the page (how Reddit records it as opened),
  // then steps back to the list, which Reddit's page moved away from.
  Future<void> _clickItem(
      InAppWebViewController p, String notificationId) async {
    final id = notificationId.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
    final clicked = await _eval(
        p,
        "(function(){var e=document.querySelector('notification-item"
        '[notification-id="$id"]\');var a=e&&e.querySelector(\'a[href]\');'
        'if(a)a.click();return !!a})()');
    if (clicked != true && clicked != 1) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_page == p && await p.canGoBack()) await p.goBack();
    // Wait for the list to be back before the next click.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_page != p) return;
      final n = await _eval(
          p, "document.querySelectorAll('notification-item').length");
      if (n is num && n > 0) return;
    }
  }

  /// Leaving the tab: the page closes shortly after (coming straight back
  /// keeps it).
  void release({Duration after = const Duration(seconds: 10)}) {
    _active = false;
    _closeTimer?.cancel();
    _closeTimer = Timer(after, () => _closeView(update: true));
  }

  void _closeView({required bool update}) {
    final v = _view;
    _view = null;
    _page = null;
    _nextUrl = null;
    v?.dispose();
    if (!update) return;
    // No page, no next batch: "Older notifications on reddit.com" stands in.
    final s = state;
    if (s is RedditNotifData && (s.hasMore || s.loadingMore)) {
      state = s.copyWith(hasMore: false, loadingMore: false);
    }
  }

  // Unread: new since last time (not among the stored "seen" ids), or Reddit
  // says it wasn't clicked; either way, not once opened in Ilay.
  List<RedditNotification> _mark(List<RedditNotification> items) {
    final seen = _recall(_seenKey);
    final opened = _recall(_openedKey);
    final firstLook = seen.isEmpty;
    final out = [
      for (final n in items)
        n.copyWith(
            unread: !opened.contains(n.id) &&
                ((!firstLook && !seen.contains(n.id)) || n.clicked == false))
    ];
    _remember(_seenKey, [for (final n in items) n.id]);
    // Opened on Reddit (its app, the site): the matching reply or mention
    // reads as read in Ilay's Inbox too. Free: the list is already read.
    final openedThere = [
      for (final n in items)
        if (n.clicked == true && n.link != null) commentIdOf(n.link!)
    ].whereType<String>().toList();
    if (openedThere.isNotEmpty) markInboxReadFromReddit(ref, openedThere);
    return out;
  }

  // Per account, as Kotlin's userScopedKey (moving a pre-account list over).
  String _key(String base) {
    final prefs = ref.read(sharedPrefsProvider);
    final key = _user.isEmpty ? base : '${base}_${_user.toLowerCase()}';
    if (key != base && !prefs.containsKey(key) && prefs.containsKey(base)) {
      final legacy = prefs.getString(base);
      if (legacy != null) prefs.setString(key, legacy);
      prefs.remove(base);
    }
    return key;
  }

  Set<String> _recall(String base) =>
      (ref.read(sharedPrefsProvider).getString(_key(base)) ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();

  void _remember(String base, List<String> ids) {
    final prefs = ref.read(sharedPrefsProvider);
    final key = _key(base);
    final all = {
      ...ids,
      ...(prefs.getString(key) ?? '').split(','),
    }.where((s) => s.isNotEmpty).take(_maxIds);
    prefs.setString(key, all.join(','));
  }

  Future<Object?> _eval(InAppWebViewController p, String js) async {
    try {
      return await p
          .evaluateJavascript(source: js)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  static Object? _json(Object? raw) {
    if (raw is! String) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<_PageResult> _open(String cookie) async {
    _closeView(update: false);
    await loadWebSessionCookies(cookie);
    final created = Completer<void>();
    late final HeadlessInAppWebView v;
    v = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(redditNotificationsUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: RedditConstants.webUserAgent,
        useShouldOverrideUrlLoading: true,
        // Only the list's text and links are read: no images, video or
        // fonts, nor Home's skippable telemetry.
        blockNetworkImage: true,
        contentBlockers: [
          ContentBlocker(
            trigger: ContentBlockerTrigger(urlFilter: '.*', resourceType: [
              ContentBlockerTriggerResourceType.IMAGE,
              ContentBlockerTriggerResourceType.MEDIA,
              ContentBlockerTriggerResourceType.FONT,
            ]),
            action:
                ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
          ),
          for (final filter in RedditHomeLoader.skippable)
            ContentBlocker(
              trigger: ContentBlockerTrigger(urlFilter: filter),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
        ],
      ),
      onWebViewCreated: (c) {
        if (_view == v) _page = c;
        if (!created.isCompleted) created.complete();
      },
      // Stay on the list: a clicked item doesn't load its post here.
      shouldOverrideUrlLoading: (_, action) async =>
          action.isForMainFrame &&
                  action.navigationType == NavigationType.LINK_ACTIVATED
              ? NavigationActionPolicy.CANCEL
              : NavigationActionPolicy.ALLOW,
      onWebContentProcessDidTerminate: (_) {
        if (_view == v) _closeView(update: true);
      },
    );
    _view = v;
    await v.run();
    await created.future.timeout(const Duration(seconds: 10));
    final deadline = DateTime.now().add(_timeout);
    DateTime? emptySince;
    while (DateTime.now().isBefore(deadline) && _view == v) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final p = _page;
      if (p == null) break;
      final json = _json(await _eval(p, _read));
      if (json is! Map) continue;
      if (json['login'] == true) {
        _closeView(update: false);
        return const _PageResult([], null, signedOut: true, ok: false);
      }
      final items = parseRedditNotifications(json);
      if (items.isNotEmpty) {
        // Reddit's read flags appear once the page has drawn its menus.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        final again = parseRedditNotifications(_json(await _eval(p, _read)));
        return _PageResult(again.length >= items.length ? again : items,
            json['next'] is String ? json['next'] as String : null,
            signedOut: false, ok: true);
      }
      // The page is up but lists nothing: give it a moment, then it's
      // really empty.
      if (json['ready'] == true) {
        final now = DateTime.now();
        emptySince ??= now;
        if (now.difference(emptySince) > const Duration(seconds: 3)) {
          return const _PageResult([], null, signedOut: false, ok: true);
        }
      }
    }
    if (_view == v) _closeView(update: false);
    return const _PageResult([], null, signedOut: false, ok: false);
  }

  // Reddit's page loads older notifications from this link as you scroll;
  // fetched from inside the page (its sign-in) and read the same way.
  Future<({List<RedditNotification> items, String? next})?> _fetchMore(
      String url) async {
    final p = _page;
    if (p == null) return null;
    try {
      final r = await p.callAsyncJavaScript(
          functionBody: '''
var r = await fetch(url, {credentials: 'include'});
var d = new DOMParser().parseFromString(await r.text(), 'text/html');
return JSON.stringify({items: ilayRead(d), next: ilayNext(d)});''',
          arguments: {'url': url}).timeout(const Duration(seconds: 12));
      if (_page != p) return null;
      final json = _json(r?.value);
      if (json is! Map) return null;
      final next = json['next'];
      return (
        items: parseRedditNotifications(json),
        next: next is String ? next : null
      );
    } catch (_) {
      return null;
    }
  }
}

final redditNotificationsProvider =
    NotifierProvider<RedditNotifications, RedditNotifState?>(
        RedditNotifications.new);
