import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/network/web_token.dart';

String jwt(DateTime exp) {
  String part(Map m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.'
      '${part({'exp': exp.millisecondsSinceEpoch ~/ 1000, 'lid': 't2_x'})}.sig';
}

void main() {
  final now = DateTime(2026, 10, 28, 12);

  test('reads, replaces, adds and removes cookies in a header', () {
    const h = 'loid=1; token_v2=old; reddit_session=s';
    expect(cookieValue(h, 'token_v2'), 'old');
    expect(cookieValue(h, 'csrf_token'), isNull);
    expect(withCookie(h, 'token_v2', 'new'),
        'loid=1; token_v2=new; reddit_session=s');
    expect(withCookie(h, 'token_v2', null), 'loid=1; reddit_session=s');
    expect(withCookie(h, 'csrf_token', 'c'),
        'loid=1; token_v2=old; reddit_session=s; csrf_token=c');
  });

  test('a token expiring soon, missing or unreadable needs renewing', () {
    String header(DateTime exp) => 'reddit_session=s; token_v2=${jwt(exp)}';
    expect(needsNewToken(header(now.add(const Duration(hours: 20))), now: now),
        isFalse);
    expect(needsNewToken(header(now.add(const Duration(minutes: 2))), now: now),
        isTrue);
    expect(needsNewToken(header(now.subtract(const Duration(days: 3))), now: now),
        isTrue);
    expect(needsNewToken('reddit_session=s', now: now), isTrue);
    expect(needsNewToken('token_v2=garbage', now: now), isTrue);
  });

  test('Set-Cookie headers update the header; deleted cookies drop out', () {
    expect(
        mergeSetCookies('loid=1; reddit_session=s', [
          'token_v2=fresh; Domain=.reddit.com; Path=/; Max-Age=86400; Secure',
          'csrf_token=c; Path=/',
          'loid=; Max-Age=0',
        ]),
        'reddit_session=s; token_v2=fresh; csrf_token=c');
  });

  test('reads the account a reddit_session belongs to', () {
    String part(String s) =>
        base64Url.encode(utf8.encode(s)).replaceAll('=', '');
    final session =
        '${part('{"alg":"RS256"}')}.${part('{"sub":"t2_abc","exp":1}')}.sig';
    expect(sessionAccount('loid=1; reddit_session=$session'), 't2_abc');
    expect(sessionAccount('loid=1; reddit_session=opaque'), isNull);
    expect(sessionAccount('loid=1'), isNull);
  });
}
