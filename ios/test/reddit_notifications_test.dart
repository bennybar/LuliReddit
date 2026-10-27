import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/network/rate_limit.dart';
import 'package:luli_for_reddit/core/widgets/error_view.dart';
import 'package:luli_for_reddit/features/inbox/reddit_notifications.dart';
import 'package:luli_for_reddit/features/notifications/inbox_poller.dart';

void main() {
  test('reads what the page lists, drops empties and repeats', () {
    final json = jsonDecode('''{"login":false,"ready":true,"items":[
      {"id":"a1","type":"POST_REPLY","link":"https://www.reddit.com/r/x/comments/p1/t/c1/","title":"u/bob replied to your post in r/x","body":"Nice!","ts":"2026-10-17T15:03:29.378Z","avatar":"https://www.redditstatic.com/a.png"},
      {"id":"a1","type":"POST_REPLY","link":null,"title":"dup","body":"","ts":null,"avatar":null},
      {"id":"a2","type":"UPVOTE_POST","link":"javascript:void(0)","title":"10 upvotes!","body":"","ts":"bad","avatar":"/rel.png"},
      {"id":"a3","type":"X","link":null,"title":"","body":"","ts":null,"avatar":null}
    ]}''');
    final items = parseRedditNotifications(json);
    expect(items.map((n) => n.id), ['a1', 'a2']);
    expect(items[0].body, 'Nice!');
    expect(items[0].at, 1792249409378);
    expect(items[1].link, isNull);
    expect(items[1].at, 0);
    expect(items[1].avatar, isNull);
  });

  test('finds the comment a notification points at', () {
    expect(
        commentIdOf('https://www.reddit.com/r/GalaxyWatch/comments/1x79dhp/'
            'new_button_remapping_app/phbdvfd/'),
        'phbdvfd');
    expect(
        commentIdOf('https://www.reddit.com/r/WearOS/comments/1x79h6q/slug/'
            'ph6woy7/?screen_view_count=1'),
        'ph6woy7');
    expect(commentIdOf('https://www.reddit.com/r/x/comments/1x/comment/abc12/'),
        'abc12');
    // A post, not a comment.
    expect(
        commentIdOf('https://www.reddit.com/r/WearOS/comments/1x79h6q/'
            'new_galaxy_watch/'),
        isNull);
  });

  test('rate-limited copy says how long to wait', () {
    final at = DateTime(2026, 1, 1, 12);
    RateLimit.latest = null;
    expect(rateLimited(at), contains('Try again shortly'));
    RateLimit.latest =
        RateLimit(remaining: 0, used: 100, resetSeconds: 45, at: at);
    expect(rateLimited(at.add(const Duration(seconds: 5))),
        'Reddit is rate-limiting for a moment. Try again in 40s.');
    RateLimit.latest =
        RateLimit(remaining: 0, used: 0, resetSeconds: 300, at: at);
    expect(rateLimited(at.add(const Duration(seconds: 50))),
        'Reddit is rate-limiting. Try again in about 5 min.');
    RateLimit.latest = null;
  });

  test('unread messages open their conversation', () {
    final m = parseUnread({
      'name': 't4_b2',
      'author': 'bob',
      'was_comment': false,
      'subject': 'hi',
      'body': 'hello\nthere',
      'first_message_name': 't4_a1',
    })!;
    expect(m.title, 'hi');
    expect(m.body, 'hello there');
    expect(m.route, '/message?id=t4_a1');
    final r = parseUnread({
      'name': 't1_c3',
      'author': 'amy',
      'was_comment': true,
      'link_title': 'A post',
      'subreddit': 'x',
      'link_id': 't3_p1',
      'body': '',
    })!;
    expect(r.title, 'u/amy replied · A post');
    expect(r.body, 'Open Ilay to read');
    expect(r.route, '/comments/x/p1?comment=c3');
  });
}
