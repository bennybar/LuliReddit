import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/feed/post_card.dart';
import 'package:luli_for_reddit/models/post.dart';

Post _poll(Map<String, dynamic> poll) => Post.fromData({
      'id': 'p1',
      'title': 'Poll',
      'subreddit': 'polls',
      'permalink': '/r/polls/comments/p1/poll/',
      'poll_data': poll,
    });

void main() {
  test('poll before voting: options only, no results', () {
    final p = _poll({
      'options': [
        {'id': '11', 'text': 'Yes'},
        {'id': '12', 'text': 'No'},
      ],
      'user_selection': null,
    });
    expect(p.pollOptions, ['Yes', 'No']);
    expect(p.pollVotes, isEmpty);
    expect(p.pollChoice, isNull);
  });

  test('poll after voting: counts and your choice line up with the options',
      () {
    final p = _poll({
      'options': [
        {'id': '11', 'text': 'Yes', 'vote_count': 30},
        {'id': 'x', 'text': ''},
        {'id': '12', 'text': 'No', 'vote_count': 10},
      ],
      'user_selection': '12',
    });
    expect(p.pollOptions, ['Yes', 'No']);
    expect(p.pollVotes, [30, 10]);
    expect(p.pollChoice, 1);
  });

  test("a crosspost of a text post shows the original's text but stays a "
      'link post', () {
    final p = Post.fromData({
      'id': 'x2',
      'title': 'Audio book app suggestion.',
      'subreddit': 'audiobookshelf',
      'url': '/r/audiobooks/comments/abc/audio_book_app_suggestion/',
      'is_self': false,
      'selftext': '',
      'crosspost_parent_list': [
        {
          'subreddit': 'audiobooks',
          'is_self': true,
          'selftext': 'Can you suggest a good app?',
          'url': 'https://www.reddit.com/r/audiobooks/comments/abc/x/',
        }
      ],
    });
    expect(p.type, PostType.self);
    expect(p.selftext, 'Can you suggest a good app?');
    expect(p.crosspostFrom, 'audiobooks');
    expect(p.isSelf, isFalse); // not editable as the user's own text
  });

  test('subreddit icon comes from sr_detail, unescaped', () {
    final p = Post.fromData({
      'id': 'a',
      'subreddit': 'x',
      'sr_detail': {
        'community_icon': 'https://styles.redditmedia.com/i.png?a=1&amp;b=2',
        'icon_img': '',
      },
    });
    expect(p.subredditIcon, 'https://styles.redditmedia.com/i.png?a=1&b=2');
    expect(Post.fromData({'id': 'b', 'subreddit': 'x'}).subredditIcon, isNull);
  });

  test('the feed snippet drops media-only paragraphs', () {
    final p = Post.fromData({
      'id': 'a',
      'subreddit': 'x',
      'is_self': true,
      'selftext': 'Look:\n\nhttps://i.redd.it/abc.jpg\n\nNice, right?',
    });
    expect(p.snippet, 'Look:\n\nNice, right?');
  });

  group('Calm flair', () {
    test('strips emoji shortcodes', () {
      expect(cleanFlair(':Discussion: Discussion'), 'Discussion');
      expect(cleanFlair('Medieval Europe :castle:'), 'Medieval Europe');
      expect(cleanFlair(':q:  Help   :x_y-1: me'), 'Help me');
    });

    test('keeps plain text and empties emoji-only flair', () {
      expect(cleanFlair('OC'), 'OC');
      expect(cleanFlair('10:30 AM'), '10:30 AM');
      expect(cleanFlair(':star:'), '');
    });
  });
}
