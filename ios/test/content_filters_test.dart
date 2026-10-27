import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/feed/content_filters.dart';
import 'package:luli_for_reddit/models/post.dart';

Post _post(String title, {String sub = 'pics', bool nsfw = false}) =>
    Post.fromData({
      'id': title.hashCode.toString(),
      'title': title,
      'subreddit': sub,
      'over_18': nsfw,
      'url': 'https://example.com',
      'domain': 'example.com',
    });

void main() {
  test('keywords match whole words only, in any script', () {
    const f = ContentFilters(keywords: ['cat', 'מלחמה']);
    expect(f.hides(_post('My cat sleeps')), isTrue);
    expect(f.hides(_post('Cat!')), isTrue);
    expect(f.hides(_post('Vacation photos')), isFalse);
    expect(f.hides(_post('Category theory')), isFalse);
    expect(f.hides(_post('עדכון מלחמה היום')), isTrue);
  });

  test('subreddit filter spares the subreddit\'s own page', () {
    const f = ContentFilters(subreddits: ['politics']);
    final p = _post('Hi', sub: 'Politics');
    expect(f.hides(p), isTrue);
    expect(f.hides(p, viewingSubreddit: 'politics'), isFalse);
  });

  test('hide NSFW', () {
    expect(const ContentFilters(hideNsfw: true).hides(_post('x', nsfw: true)),
        isTrue);
    expect(const ContentFilters().hides(_post('x', nsfw: true)), isFalse);
  });
}
