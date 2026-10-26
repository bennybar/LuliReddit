import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/feed/local_votes.dart';

void main() {
  test('Reddit still has the old vote: show yours on its score', () {
    final v = LocalVotes()..record('a', 1, 10, null);
    expect(v.reconcile('a', null, 10), (true, 11));
    // Someone else voted meanwhile: their vote counts, yours is added on top.
    expect(v.reconcile('a', null, 12), (true, 13));
  });

  test('vote is in but score has not moved: add it', () {
    final v = LocalVotes()..record('a', 1, 10, null);
    expect(v.reconcile('a', true, 10), (true, 11));
  });

  test('Reddit caught up: trust it from then on', () {
    final v = LocalVotes()..record('a', -1, 10, null);
    expect(v.reconcile('a', false, 9), (false, 9));
    expect(v.reconcile('a', false, 7), (false, 7));
  });

  test('changing a vote twice keeps the first baseline', () {
    final v = LocalVotes();
    v.reconcile('a', true, 20); // seen: upvoted at 20
    v.record('a', 0, 20, true);
    v.record('a', -1, 19, null);
    expect(v.reconcile('a', true, 20), (false, 18));
    expect(v.reconcile('a', false, 20), (false, 18));
  });

  test('no local vote: server wins', () {
    expect(LocalVotes().reconcile('a', null, 5), (null, 5));
  });
}
