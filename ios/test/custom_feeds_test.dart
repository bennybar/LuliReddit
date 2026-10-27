import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/widgets/connected_choice.dart';
import 'package:luli_for_reddit/features/search/saved_searches.dart';
import 'package:luli_for_reddit/models/multireddit.dart';

void main() {
  test('multiSlug makes a path-safe feed name', () {
    expect(multiSlug('My Cool Feed!'), 'my_cool_feed');
    expect(multiSlug('  __Tech & News__ '), 'tech_news');
    expect(multiSlug('!!!'), 'feed');
    expect(multiSlug('a' * 60).length, 50);
  });

  test('Multireddit.owner reads the path, else falls back', () {
    const m = Multireddit(
        name: 'feed', displayName: 'Feed', path: '/user/Bob/m/feed/',
        subreddits: []);
    expect(m.owner('me'), 'Bob');
    const bare = Multireddit(
        name: 'feed', displayName: 'Feed', path: '', subreddits: []);
    expect(bare.owner('me'), 'me');
  });

  test('SavedSearch key ignores case of words and subreddit', () {
    const a = SavedSearch('Cats', 'Pics', 'top', 'week');
    const b = SavedSearch('cats', 'pics', 'top', 'week');
    const c = SavedSearch('cats', null, 'top', 'week');
    expect(a.key, b.key);
    expect(a.key == c.key, isFalse);
    expect(c.toJson().containsKey('sr'), isFalse);
  });

  testWidgets('ConnectedChoice reports the tapped option', (tester) async {
    var picked = 'private';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (_, setState) => ConnectedChoice<String>(
            options: const [('private', 'Private'), ('public', 'Public')],
            selected: picked,
            onSelect: (v) => setState(() => picked = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    expect(picked, 'public');
  });
}
