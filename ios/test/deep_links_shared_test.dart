import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/deep_links.dart';

void main() {
  test('a share-extension link carries the reddit url and the mode', () {
    final url = 'https://www.reddit.com/r/apple/s/AbCdEf';
    final s = sharedLink(Uri.parse(
        'luli://share?url=${Uri.encodeQueryComponent(url)}&summarize=1'))!;
    expect(s.url.toString(), url);
    expect(s.summarize, isTrue);
    expect(
        sharedLink(Uri.parse(
                'luli://share?url=${Uri.encodeQueryComponent(url)}'))!
            .summarize,
        isFalse);
  });

  test('other links are not share-extension links', () {
    expect(sharedLink(Uri.parse('luli://oauth?code=x')), isNull);
    expect(sharedLink(Uri.parse('luli://share?url=https://example.com/a')),
        isNull);
  });

  test('post id from a post route', () {
    expect(postIdInRoute('/comments/apple/abc123'), 'abc123');
    expect(postIdInRoute('/comments/_/abc123?comment=x'), 'abc123');
    expect(postIdInRoute('/r/apple'), isNull);
  });

  test('custom feed share links resolve first, not to the user', () {
    final feed = Uri.parse('https://www.reddit.com/u/abidd43/s/kAKtvQZpm9');
    expect(isShareLink(feed), isTrue);
    expect(routeForRedditUrl(feed), isNull);
    expect(isShareLink(Uri.parse('https://www.reddit.com/u/abidd43')), isFalse);
    expect(
        routeForRedditUrl(
            Uri.parse('https://www.reddit.com/user/abidd43/m/ask_stuff/')),
        '/m/abidd43/ask_stuff');
  });
}
