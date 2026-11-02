import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/history/history_store.dart';

void main() {
  RecentSubreddit r(String name) =>
      RecentSubreddit(name: name, namePrefixed: 'r/$name');

  test('newest first, once per subreddit whatever the case, at most five', () {
    var list = <RecentSubreddit>[];
    for (final n in ['a', 'b', 'c', 'd', 'e', 'f']) {
      list = RecentSubredditsController.visited(list, r(n));
    }
    expect(list.map((e) => e.name), ['f', 'e', 'd', 'c', 'b']);
    list = RecentSubredditsController.visited(list, r('C'));
    expect(list.map((e) => e.name), ['C', 'f', 'e', 'd', 'b']);
  });

  test('survives a round trip through JSON', () {
    final back = RecentSubreddit.fromJson(const RecentSubreddit(
            name: 'a', namePrefixed: 'r/a', iconUrl: 'u', subscribers: 7)
        .toJson());
    expect(back.asSubreddit().namePrefixed, 'r/a');
    expect(back.asSubreddit().iconUrl, 'u');
    expect(back.asSubreddit().subscribers, 7);
  });
}
