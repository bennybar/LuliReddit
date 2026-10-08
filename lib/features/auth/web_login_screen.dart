import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/reddit_constants.dart';

/// A WebView that signs the user into reddit.com and returns the resulting
/// session-cookie header string (or null if cancelled). This is the no-API-key
/// "website session" login — see docs/hydra-fallback.md. The user's password is
/// only ever entered into Reddit's own page inside the WebView.
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key, this.clearFirst = false});

  /// Wipe existing cookies first, so you can sign into a *different* account
  /// (used by "add account").
  final bool clearFirst;

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  Timer? _poll;
  bool _done = false;
  // With clearFirst, the old cookies must be gone before the page loads or the
  // session check runs — otherwise it finds the *current* account's
  // reddit_session straight away and adds that account again.
  late bool _ready = !widget.clearFirst;

  @override
  void initState() {
    super.initState();
    if (_ready) {
      _startPolling();
    } else {
      CookieManager.instance().deleteAllCookies().whenComplete(() {
        if (!mounted) return;
        setState(() => _ready = true);
        _startPolling();
      });
    }
  }

  void _startPolling() => _poll = Timer.periodic(
    const Duration(milliseconds: 700),
    (_) => _check(),
  );

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_done) return;
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri(RedditConstants.webApiBase));
    final hasSession =
        cookies.any((c) => c.name == 'reddit_session' && '${c.value}'.isNotEmpty);
    if (!hasSession) return;
    _done = true;
    _poll?.cancel();
    final header =
        cookies.map((c) => '${c.name}=${c.value}').join('; ');
    if (mounted) Navigator.of(context).pop(header);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in to Reddit'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(RedditConstants.webLoginUrl),
              ),
              initialSettings: InAppWebViewSettings(
                userAgent: RedditConstants.webUserAgent,
                javaScriptEnabled: true,
                clearCache: widget.clearFirst,
              ),
              onLoadStop: (_, __) => _check(),
            ),
    );
  }
}
