import 'package:flutter_inappwebview/flutter_inappwebview.dart';

final _reddit = WebUri('https://www.reddit.com/');

/// Puts the active website session ([cookieHeader]) in the WebView cookie
/// jar, which every WebView shares (hidden Home, signed-in pages). The jar may
/// hold a different account's session (the last one that signed in through
/// it).
Future<void> loadWebSessionCookies(String cookieHeader) async {
  final jar = CookieManager.instance();
  final inJar = await jar.getCookie(url: _reddit, name: 'reddit_session');
  String? session(String header) => header
      .split(';')
      .map((p) => p.trim())
      .where((p) => p.startsWith('reddit_session='))
      .firstOrNull
      ?.substring('reddit_session='.length);
  // Same account already in the jar: keep it as is. Wiping it also threw
  // away the cookies Reddit set when the page passed its browser check, so
  // every launch had to pass that check again (an extra page load).
  if (inJar?.value?.toString() == session(cookieHeader)) return;
  await jar.deleteCookies(url: _reddit, domain: '.reddit.com');
  for (final part in cookieHeader.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    await jar.setCookie(
      url: _reddit,
      name: part.substring(0, i).trim(),
      value: part.substring(i + 1).trim(),
      domain: '.reddit.com',
      isSecure: true,
    );
  }
}
