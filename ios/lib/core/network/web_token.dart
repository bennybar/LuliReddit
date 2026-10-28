import 'dart:convert';

import 'package:dio/dio.dart';

import '../reddit_constants.dart';

// Website sign-in sends the cookies captured at login. Their `token_v2` (a
// JWT, valid for about a day) is also the bearer token for Reddit's app
// GraphQL API, which search needs (RedditClient.gql). Page loads stopped
// renewing it in October 2026, but a request to the website that carries no
// token_v2 still gets a new one.

/// The value of cookie [name] in a Cookie header.
String? cookieValue(String header, String name) {
  for (final part in header.split(';')) {
    final p = part.trim();
    if (p.startsWith('$name=')) return p.substring(name.length + 1);
  }
  return null;
}

/// [header] with cookie [name] set to [value] (in place), or removed when
/// [value] is null.
String withCookie(String header, String name, String? value) {
  final parts = [
    for (final part in header.split(';'))
      if (part.trim().isNotEmpty) part.trim()
  ];
  final i = parts.indexWhere((p) => p.startsWith('$name='));
  if (value == null) {
    if (i >= 0) parts.removeAt(i);
  } else if (i >= 0) {
    parts[i] = '$name=$value';
  } else {
    parts.add('$name=$value');
  }
  return parts.join('; ');
}

/// When a token_v2 JWT expires; null if it can't be read.
DateTime? tokenExpiry(String token) {
  try {
    final payload = token.split('.')[1];
    final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload)))) as Map;
    final exp = claims['exp'];
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).toInt())
        : null;
  } catch (_) {
    return null;
  }
}

/// Whether [cookieHeader]'s token_v2 is missing or expires within 5 minutes.
bool needsNewToken(String cookieHeader, {DateTime? now}) {
  final token = cookieValue(cookieHeader, 'token_v2');
  final expiry = token == null ? null : tokenExpiry(token);
  return expiry == null ||
      expiry.isBefore(
          (now ?? DateTime.now()).add(const Duration(minutes: 5)));
}

/// [header] with the cookies a response's Set-Cookie headers set (a deleted
/// or emptied cookie is left out).
String mergeSetCookies(String header, List<String> setCookies) {
  var out = header;
  for (final sc in setCookies) {
    final pair = sc.split(';').first;
    final i = pair.indexOf('=');
    if (i <= 0) continue;
    final name = pair.substring(0, i).trim();
    final value = pair.substring(i + 1).trim();
    final gone = value.isEmpty || sc.toLowerCase().contains('max-age=0');
    out = withCookie(out, name, gone ? null : value);
  }
  return out;
}

/// Gets a new token_v2 for [cookieHeader]'s session: the page (which sets it,
/// with loid, csrf_token…), then the website's GraphQL proxy, which also sets
/// it even though it rejects the empty request. Returns the updated header, or null
/// when Reddit didn't issue a fresh token.
Future<String?> renewWebToken(String cookieHeader) async {
  final dio = Dio(BaseOptions(
    validateStatus: (_) => true,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));
  // Reddit only issues a token to a request that doesn't carry one.
  var cookie = withCookie(cookieHeader, 'token_v2', null);
  Map<String, String> headers() => {
        'cookie': cookie,
        'User-Agent': RedditConstants.webUserAgent,
      };
  try {
    final page = await dio.head<void>('${RedditConstants.webApiBase}/',
        options: Options(headers: headers(), followRedirects: false));
    cookie = mergeSetCookies(cookie, page.headers['set-cookie'] ?? const []);
    final proxy = await dio.post<void>(
        '${RedditConstants.webApiBase}/svc/shreddit/graphql',
        data: '{}',
        options: Options(headers: {
          ...headers(),
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        }));
    cookie = mergeSetCookies(cookie, proxy.headers['set-cookie'] ?? const []);
  } on DioException {
    return null;
  }
  return needsNewToken(cookie) ? null : cookie;
}
