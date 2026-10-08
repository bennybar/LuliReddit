import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/foryou/for_you_ranker.dart';
import 'package:luli_for_reddit/features/foryou/for_you_stores.dart';
import 'package:luli_for_reddit/features/history/interest_store.dart';
import 'package:luli_for_reddit/models/post.dart';

final _now = DateTime.utc(2026, 10, 8, 12);
var _n = 0;

Post _p(String sub, String title,
    {int score = 500, double hoursOld = 3, String? url, double ratio = 0.9}) {
  final id = 'p${_n++}';
  return Post.fromData({
    'id': id,
    'title': title,
    'subreddit': sub,
    'score': score,
    'upvote_ratio': ratio,
    'created_utc':
        _now.subtract(Duration(minutes: (hoursOld * 60).round())).millisecondsSinceEpoch ~/ 1000,
    'url': url ?? 'https://www.reddit.com/r/$sub/comments/$id/',
    'is_self': url == null,
    'permalink': '/r/$sub/comments/$id/',
  });
}

List<Candidate> _c(List<Post> ps, [String src = 'best']) =>
    [for (final p in ps) Candidate(p, src)];

void main() {
  test('B5: a strongly disliked topic never flips the ordering', () {
    final fav = _p('formula1', 'Election chaos in the paddock election votes',
        hoursOld: 72);
    final disc = _p('random', 'Some unrelated discovery post', hoursOld: 72);
    final r = rankForYou(
        _c([fav, disc]),
        RankInputs(
          favourites: {'formula1'},
          subscribed: {'formula1'},
          keywordScore: (t) => t.contains('Election') ? -6 : 0,
          now: _now,
        ));
    expect(r.ranked.first.id, fav.id,
        reason: 'favourite × 4 must still beat discovery × 0.4');
  });

  test('B5: an opened post ranks below an unopened twin', () {
    final opened = _p('a', 'Twin post one');
    final fresh = _p('a', 'Twin post two');
    final r = rankForYou(
        _c([opened, fresh]),
        RankInputs(
          subscribed: {'a'},
          keywordScore: (_) => -6,
          openedAt: {opened.id: _now.millisecondsSinceEpoch - 3600 * 1000},
          now: _now,
        ));
    expect(r.ranked.first.id, fresh.id);
  });

  test('B1: negative interest and "less from" actually demote', () {
    // Distinct titles, or the same-story rule would merge them.
    const words = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot'];
    final news = [for (final w in words) _p('news', 'Report $w')];
    final pics = [for (final w in words) _p('pics', 'Photo $w')];
    int newsInTop6(RankInputs i) => rankForYou(_c([...news, ...pics]), i)
        .ranked
        .take(6)
        .where((p) => p.subreddit == 'news')
        .length;
    final neutral = newsInTop6(RankInputs(subscribed: {'news', 'pics'}, now: _now));
    final learnedLess = newsInTop6(RankInputs(
        subscribed: {'news', 'pics'}, interest: {'news': -8}, now: _now));
    final askedLess = newsInTop6(RankInputs(
        subscribed: {'news', 'pics'},
        explicit: const ExplicitPrefs(subs: {'news': -1}),
        now: _now));
    expect(learnedLess, lessThan(neutral));
    expect(askedLess, lessThan(neutral));
  });

  test('same link in two places is kept once', () {
    final a = _p('tech', 'Big article', url: 'https://www.example.com/x?utm_source=r');
    final b = _p('news', 'Big article again', url: 'https://example.com/x');
    final r = rankForYou(_c([a, b]), RankInputs(subscribed: {'tech', 'news'}, now: _now));
    expect(r.ranked.length, 1);
  });

  test('same story: second copy spaced out, third dropped', () {
    final story = [
      for (final s in ['a', 'b', 'c'])
        _p(s, 'Starship launch succeeds orbital flight test today')
    ];
    final filler = [for (var i = 0; i < 30; i++) _p('f$i', 'Filler post about thing$i')];
    final r = rankForYou(_c([...story, ...filler]),
        RankInputs(subscribed: {'a', 'b', 'c', for (var i = 0; i < 30; i++) 'f$i'}, now: _now));
    final pos = [
      for (var i = 0; i < r.ranked.length; i++)
        if (r.ranked[i].title.startsWith('Starship')) i
    ];
    expect(pos.length, 2);
    expect(pos[1] - pos[0], greaterThanOrEqualTo(15));
  });

  test('diversity: no long runs from one subreddit; overflow carries over', () {
    // One subreddit with the strongest posts, and plenty of alternatives.
    final big = [
      for (var i = 0; i < 20; i++) _p('big', 'Big item $i', score: 5000 + i * 100)
    ];
    final small = [for (var i = 0; i < 20; i++) _p('s$i', 'Small item $i', score: 50)];
    final r = rankForYou(_c([...big, ...small]),
        RankInputs(subscribed: {'big', for (var i = 0; i < 20; i++) 's$i'}, now: _now),
        pageSize: 20);
    var run = 1, longest = 1;
    for (var i = 1; i < r.ranked.length; i++) {
      run = r.ranked[i].subreddit == r.ranked[i - 1].subreddit ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    expect(longest, lessThanOrEqualTo(2));
    expect(r.leftovers, isNotEmpty);
  });

  test('explanations come from what drove the score', () {
    final p = _p('formula1', 'Verstappen wins again');
    final r = rankForYou(_c([p]),
        RankInputs(
          subscribed: {'formula1'},
          explicit: const ExplicitPrefs(topics: {'verstappen': 1}),
          now: _now,
        ));
    expect(r.ranked.single.feedReason, contains('verstappen'));
    expect(r.meta[p.id]!.why, isNotEmpty);
  });

  test('tokenizer: Hebrew, acronyms, accents', () {
    expect(titleKeywords('הבחירות לכנסת בשבוע הבא'), contains('בחירות'));
    expect(titleKeywords('F1 and NBA news on PS5'), containsAll(['f1', 'nba', 'ps5']));
    expect(titleKeywords('New Pokémon game announced'), contains('pokémon'));
    expect(titleKeywords('this is just the help'), isNot(contains('this')));
  });
}
