import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/models/post.dart';

void main() {
  test('Post.fromData parses an image post', () {
    final post = Post.fromData({
      'id': 'abc',
      'name': 't3_abc',
      'title': 'Hello world',
      'subreddit': 'flutter',
      'subreddit_name_prefixed': 'r/flutter',
      'author': 'someone',
      'score': 1234,
      'num_comments': 56,
      'upvote_ratio': 0.97,
      'created_utc': 1700000000,
      'permalink': '/r/flutter/comments/abc/hello',
      'url': 'https://i.redd.it/x.jpg',
      'domain': 'i.redd.it',
      'post_hint': 'image',
      'preview': {
        'images': [
          {
            'source': {'url': 'https://i.redd.it/x.jpg', 'width': 800, 'height': 600}
          }
        ]
      },
    });

    expect(post.id, 'abc');
    expect(post.type, PostType.image);
    expect(post.score, 1234);
    expect(post.previewWidth, 800);
    expect(post.subredditPrefixed, 'r/flutter');
  });

  test('Post.fromData detects a self post', () {
    final post = Post.fromData({
      'id': 'def',
      'title': 'A text post',
      'subreddit': 'AskReddit',
      'is_self': true,
      'selftext': 'body text',
      'created_utc': 1700000000,
    });
    expect(post.type, PostType.self);
    expect(post.isSelf, true);
    expect(post.selftext, 'body text');
  });
}
