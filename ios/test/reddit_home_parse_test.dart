import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/reddit_home/reddit_home_loader.dart';
import 'package:luli_for_reddit/models/post.dart';

/// What the hidden page's script returns (a JSON string).
String _page(List<Map<String, Object?>> posts, {bool signedOut = false}) =>
    jsonEncode({'signedOut': signedOut, 'posts': posts});

const _video = {
  'id': 't3_abc',
  'title': '  A video  ',
  'sub': 'r/videos',
  'author': 'someone',
  'subIcon': 'https://styles.redditmedia.com/icon.png',
  'score': '1234',
  'comments': '56',
  'created': '2026-10-20T12:00:00.000000+0000',
  'type': 'video',
  'permalink': '/r/videos/comments/abc/a_video/',
  'href': 'https://v.redd.it/xyz123',
  'domain': 'v.redd.it',
  'img': '',
  'body': '',
  'flair': 'Funny',
  'nsfw': false,
  'spoiler': true,
  'reason': 'Because you visited r/movies',
  'fewer': true,
};

void main() {
  test('reads the page: posts in order, ads and non-posts skipped', () {
    final r = HomePageRead.parse(_page([
      _video,
      {'id': 'ad_1', 'title': 'Not a post'},
      {'id': 't3_def', 'title': 'Text', 'type': 'text', 'author': ''},
    ]))!;
    expect(r.signedOut, isFalse);
    expect([for (final p in r.posts) p.id], ['t3_abc', 't3_def']);
    expect(r.posts[1].author, '[deleted]');
    expect(r.posts[1].canShowFewer, isFalse);
  });

  test('the logged-out site, and a page still reloading', () {
    expect(HomePageRead.parse(_page(const [], signedOut: true))!.signedOut,
        isTrue);
    expect(HomePageRead.parse(null), isNull);
    expect(HomePageRead.parse('null'), isNull);
  });

  test('a page post makes a feed card', () {
    final p = PagePost.parse(_video)!;
    expect(p.reason, 'Because you visited r/movies');
    expect(p.canShowFewer, isTrue);
    final post = p.toPost();
    expect(post.id, 'abc');
    expect(post.fullname, 't3_abc');
    expect(post.title, 'A video');
    expect(post.subreddit, 'videos');
    expect(post.subredditPrefixed, 'r/videos');
    expect(post.score, 1234);
    expect(post.numComments, 56);
    expect(post.created, DateTime.utc(2026, 10, 20, 12));
    expect(post.type, PostType.video);
    expect(post.hlsUrl, 'https://v.redd.it/xyz123/HLSPlaylist.m3u8');
    expect(post.feedReason, 'Because you visited r/movies');
    expect(post.linkFlairText, 'Funny');
    expect(post.spoiler, isTrue);
    expect(post.previewUrl, isNull);
  });

  test('an unknown type with an image is an image card', () {
    final post = PagePost.parse({
      'id': 't3_x',
      'type': 'crosspost',
      'img': 'https://preview.redd.it/x.jpg',
      'permalink': '/r/a/comments/x/',
    })!
        .toPost();
    expect(post.type, PostType.image);
    expect(post.url, 'https://www.reddit.com/r/a/comments/x/');
  });
}
