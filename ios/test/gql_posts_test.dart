import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/data/gql_posts.dart';
import 'package:luli_for_reddit/models/post.dart';

Map<String, dynamic> node(Map<String, dynamic> extra) => {
      '__typename': 'SubredditPost',
      'id': 't3_abc',
      'postTitle': 'A post',
      'authorInfo': {'name': 'someone'},
      'subreddit': {
        'name': 'pics',
        'prefixedName': 'r/pics',
        'styles': {'icon': 'https://styles.redditmedia.com/icon.png?width=256'},
      },
      'score': 10,
      'commentCount': 2,
      'createdAt': '2026-10-04T00:26:11.575000+0000',
      'permalink': '/r/pics/comments/abc/a_post/',
      ...extra,
    };

void main() {
  test('a gallery keeps every image', () {
    final p = Post.fromData(gqlPostData(node({
      'url': 'https://www.reddit.com/gallery/abc',
      'gallery': {
        'items': [
          {'media': {'url': 'https://i.redd.it/1.jpg', 'width': 800, 'height': 600}},
          {'media': {'url': 'https://i.redd.it/2.jpg', 'width': 600, 'height': 800}},
        ],
      },
    })));
    expect(p.gallery.map((g) => g.url),
        ['https://i.redd.it/1.jpg', 'https://i.redd.it/2.jpg']);
    expect(p.gallery.first.width, 800);
    expect(p.subredditIcon, 'https://styles.redditmedia.com/icon.png');
    expect(p.created.toUtc(), DateTime.utc(2026, 10, 4, 0, 26, 11));
  });

  test('a video gets its stream, a GIF its mp4', () {
    final video = Post.fromData(gqlPostData(node({
      'url': 'https://v.redd.it/xyz',
      'media': {
        'streaming': {'hlsUrl': 'https://v.redd.it/xyz/HLSPlaylist.m3u8'},
      },
    })));
    expect(video.hlsUrl, 'https://v.redd.it/xyz/HLSPlaylist.m3u8');
    final gif = Post.fromData(gqlPostData(node({
      'url': 'https://i.redd.it/a.gif',
      'media': {
        'still': {'source': {'url': 'https://p/a.png', 'dimensions': {'width': 400, 'height': 300}}},
        'animated': {'mp4_source': {'url': 'https://p/a.mp4'}},
      },
    })));
    expect(gif.gifMp4Url, 'https://p/a.mp4');
    expect(gif.previewUrl, 'https://p/a.png');
  });

  test('a crosspost carries the original post', () {
    final p = Post.fromData(gqlPostData(node({
      'url': '/r/other/comments/orig/',
      'crosspostRoot': {
        'post': node({
          'id': 't3_orig',
          'subreddit': {'name': 'other'},
          'url': 'https://i.redd.it/o.jpg',
          'media': {
            'still': {'source': {'url': 'https://p/o.jpg', 'dimensions': {'width': 10, 'height': 10}}},
          },
        }),
      },
    })));
    expect(p.crosspostFrom, 'other');
  });

  test('only posts count', () {
    expect(gqlIsPost({'__typename': 'SubredditPost'}), isTrue);
    expect(gqlIsPost({'__typename': 'UnavailablePost'}), isFalse);
  });
}
