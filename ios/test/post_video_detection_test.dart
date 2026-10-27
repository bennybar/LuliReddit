import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/models/post.dart';

void main() {
  test('a crossposted v.redd.it video is a video, not a link', () {
    // Shape of a real crosspost: no media of its own, the video on the parent.
    final p = Post.fromData({
      'id': 'x1',
      'title': 'Crossposted clip',
      'subreddit': 'funny',
      'url': 'https://v.redd.it/abc123',
      'domain': 'v.redd.it',
      'is_video': false,
      'media': null,
      'crosspost_parent_list': [
        {
          'subreddit': 'videos',
          'is_video': true,
          'media': {
            'reddit_video': {
              'hls_url': 'https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1',
              'fallback_url': 'https://v.redd.it/abc123/DASH_720.mp4',
            }
          },
        }
      ],
    });
    expect(p.type, PostType.video);
    expect(p.hlsUrl, 'https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1');
    expect(p.fallbackVideoUrl, 'https://v.redd.it/abc123/DASH_720.mp4');
  });

  test('a crossposted gallery is a gallery', () {
    final p = Post.fromData({
      'id': 'x2',
      'title': 'Crossposted gallery',
      'url': 'https://www.reddit.com/gallery/g1',
      'crosspost_parent_list': [
        {
          'gallery_data': {
            'items': [
              {'media_id': 'm1'}
            ]
          },
          'media_metadata': {
            'm1': {
              's': {'u': 'https://preview.redd.it/m1.jpg', 'x': 800, 'y': 600}
            }
          },
        }
      ],
    });
    expect(p.type, PostType.gallery);
    expect(p.gallery.single.url, 'https://preview.redd.it/m1.jpg');
  });

  test('a bare v.redd.it link with no metadata gets its HLS stream', () {
    final p = Post.fromData({
      'id': 'x3',
      'title': 'Bare link',
      'url': 'https://v.redd.it/zzz999',
      'domain': 'v.redd.it',
    });
    expect(p.type, PostType.video);
    expect(p.hlsUrl, 'https://v.redd.it/zzz999/HLSPlaylist.m3u8');
  });

  test('an ordinary link is still a link', () {
    final p = Post.fromData({
      'id': 'x4',
      'title': 'Article',
      'url': 'https://example.com/story',
      'domain': 'example.com',
    });
    expect(p.type, PostType.link);
    expect(p.hlsUrl, isNull);
  });
}
