import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import '../../core/network/web_session_cookies.dart';
import '../../core/open_link.dart';
import '../../core/reddit_constants.dart';
import '../../core/widgets/loading.dart';
import '../auth/auth_controller.dart';

/// Reddit pages Ilay opens signed in (website sign-in only).
class RedditWeb {
  static const chat = 'https://chat.reddit.com/';
  static const settings = 'https://www.reddit.com/settings';

  /// The `/reddit_web` route for [url], titled [title].
  static String route(String url, String title) => Uri(
      path: '/reddit_web',
      queryParameters: {'url': url, 'title': title}).toString();

  /// The post whose poll was just opened on Reddit to vote: its thread
  /// reloads the results when you come back.
  static String? pollVoteOpened;
}

/// Whether the active account signed in with the website session (signed-in
/// Reddit pages work).
final webSignInProvider = Provider.autoDispose<bool>(
    (ref) => ref.watch(authModeProvider).valueOrNull == 'web');

// Reddit sizes Chat to 100dvh, which the WebView can report as 0 (a blank
// page); and its "Skip to …" links show up as a stuck pill.
const _fixCss = "(function(){if(document.getElementById('ilay-fix'))return;"
    "var s=document.createElement('style');s.id='ilay-fix';"
    "s.textContent='reddit-chat-fullscreen{height:auto!important}"
    'a[href="#main-content"],a[href="#main-right-content"]'
    "{display:none!important}';document.head.appendChild(s)})()";

/// A reddit.com page signed in as you (website sign-in): notifications, chat,
/// a poll, Reddit's settings. Links to posts, profiles and communities open
/// in Ilay instead; other sites open in the browser. Its own WebView, so
/// Home's hidden page (and its place) is left alone.
class RedditWebScreen extends ConsumerStatefulWidget {
  const RedditWebScreen({super.key, required this.url, required this.title});
  final String url;
  final String title;

  @override
  ConsumerState<RedditWebScreen> createState() => _RedditWebScreenState();
}

class _RedditWebScreenState extends ConsumerState<RedditWebScreen> {
  // null while loading the session into the cookie jar; false = not signed in
  // on the web.
  bool? _ready;
  InAppWebViewController? _view;
  // Its own notifier: progress ticks repaint the bar, not the page.
  final _progress = ValueNotifier<int>(0);
  bool _canGoBack = false;
  bool _crashed = false;
  late final String? _startRoute =
      routeForRedditUrl(Uri.tryParse(widget.url) ?? Uri());

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    String? cookie;
    try {
      final store = ref.read(secureStoreProvider);
      if (await store.authMode == 'web') cookie = await store.webCookie;
    } catch (_) {/* not signed in on the web */}
    if (cookie == null || cookie.isEmpty) {
      if (mounted) setState(() => _ready = false);
      return;
    }
    await loadWebSessionCookies(cookie);
    if (mounted) setState(() => _ready = true);
  }

  // A post / profile / community link opens natively (not the page you came
  // for).
  bool _openNatively(Uri uri) {
    final route = routeForRedditUrl(uri);
    if (route == null || route == _startRoute || !mounted) return false;
    context.push(route);
    return true;
  }

  static bool _isReddit(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return true;
    return host == 'reddit.com' ||
        host.endsWith('.reddit.com') ||
        host.endsWith('.redditmedia.com') ||
        host.endsWith('.redditstatic.com') ||
        host == 'redd.it';
  }

  Future<void> _updateBack() async {
    final can = await _view?.canGoBack() ?? false;
    if (mounted && can != _canGoBack) setState(() => _canGoBack = can);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Widget body;
    if (_ready == null) {
      body = const Center(child: Loading());
    } else if (_ready == false || _crashed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _crashed
                    ? 'The page stopped working.'
                    : 'This page needs the website sign-in '
                        '(Settings → Login method).',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => openInBrowser(context, Uri.parse(widget.url)),
                child: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              userAgent: RedditConstants.webUserAgent,
              useShouldOverrideUrlLoading: true,
              thirdPartyCookiesEnabled: true,
            ),
            onWebViewCreated: (c) => _view = c,
            onProgressChanged: (_, p) => _progress.value = p,
            shouldOverrideUrlLoading: (c, action) async {
              final u = action.request.url;
              if (u == null || action.isForMainFrame == false) {
                return NavigationActionPolicy.ALLOW;
              }
              if (_openNatively(u)) return NavigationActionPolicy.CANCEL;
              if (u.scheme == 'http' || u.scheme == 'https') {
                if (_isReddit(u)) return NavigationActionPolicy.ALLOW;
                if (mounted) openInBrowser(context, u);
              }
              // Other sites, and app links (mailto:, intent: …).
              return NavigationActionPolicy.CANCEL;
            },
            onLoadStart: (_, __) => _updateBack(),
            onLoadStop: (c, _) => c.evaluateJavascript(source: _fixCss),
            // Reddit's pages switch "pages" in-place (no load to intercept):
            // catch a move to a post the same way, and step back.
            onUpdateVisitedHistory: (c, url, isReload) async {
              await _updateBack();
              if (isReload == true || url == null) return;
              if (_openNatively(url) && await c.canGoBack()) await c.goBack();
            },
            // The page's process died: drop the page rather than show a blank
            // one.
            onWebContentProcessDidTerminate: (_) {
              _view = null;
              if (mounted) setState(() => _crashed = true);
            },
          ),
          ValueListenableBuilder<int>(
            valueListenable: _progress,
            builder: (_, p, __) => p > 0 && p < 100
                ? LinearProgressIndicator(value: p / 100)
                : const SizedBox.shrink(),
          ),
        ],
      );
    }
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _view?.goBack();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _view?.reload(),
            ),
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () async {
                final now = await _view?.getUrl();
                if (!context.mounted) return;
                openInBrowser(context, now ?? Uri.parse(widget.url));
              },
            ),
          ],
        ),
        body: body,
      ),
    );
  }
}
