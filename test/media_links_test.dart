import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/media_links.dart';
import 'package:luli_for_reddit/features/media/media_viewers.dart';

List<String> texts(List<BodySegment> s) => [
      for (final x in s)
        x.markdown != null ? 'T:${x.markdown}' : 'M:${x.media}'
    ];

/// Port of the Android app's MediaLinksTest.
void main() {
  test('a paragraph that is only a media link becomes media in place', () {
    const body = 'Look at this\n\n'
        'https://preview.redd.it/abc.png?width=640&s=x\n\nThat\'s it';
    expect(texts(bodySegments(body, const {}, 10)), [
      'T:Look at this',
      'M:https://preview.redd.it/abc.png?width=640&s=x',
      "T:That's it",
    ]);
  });

  test('markdown link to an image counts as a lone media paragraph', () {
    expect(
        texts(bodySegments('[image](https://i.redd.it/xyz.jpg)', const {}, 10)),
        ['M:https://i.redd.it/xyz.jpg']);
  });

  test('uploaded media refs resolve from media_metadata', () {
    expect(
        texts(bodySegments('before ![img](abc123) after',
            {'abc123': 'https://i.redd.it/abc123.png'}, 10)),
        ['T:before', 'M:https://i.redd.it/abc123.png', 'T:after']);
  });

  test('media inside a sentence follows its paragraph; plain links stay text',
      () {
    const body = 'see https://i.redd.it/a.jpg here and https://example.com';
    expect(texts(bodySegments(body, const {}, 10)),
        ['T:$body', 'M:https://i.redd.it/a.jpg']);
  });

  test('media count is capped', () {
    final body = [for (var i = 1; i <= 5; i++) 'https://i.redd.it/$i.jpg']
        .join('\n\n');
    expect(
        bodySegments(body, const {}, 2).where((s) => s.media != null).length,
        2);
  });

  test('an embedded reddit video link is its v.redd.it video', () {
    final u =
        Uri.parse('https://reddit.com/link/pdnkxg6/video/pom8yboslath1/player');
    expect(inlineRedditVideo(u).toString(), 'https://v.redd.it/pom8yboslath1');
    expect(
        inlineRedditVideo(
            Uri.parse('https://www.reddit.com/r/videos/comments/abc/x/')),
        isNull);
    expect(
        resolveVideoUrl(
            'https://reddit.com/link/pdnkxg6/video/pom8yboslath1/player'),
        'https://v.redd.it/pom8yboslath1/HLSPlaylist.m3u8');
    expect(resolveVideoUrl('https://v.redd.it/abc'),
        'https://v.redd.it/abc/HLSPlaylist.m3u8');
    expect(resolveVideoUrl('https://i.imgur.com/a.gifv'),
        'https://i.imgur.com/a.mp4');
  });

  test("an invalid or missing giphy entry falls back to giphy's own copy", () {
    expect(
        texts(bodySegments(
            "I could've taken him down!\n![gif](giphy|7AoJzTRD1WzOU)",
            const {},
            3)),
        [
          "T:I could've taken him down!",
          'M:https://media.giphy.com/media/7AoJzTRD1WzOU/giphy.webp',
        ]);
    expect(giphyUrl('abc123'), isNull);
    expect(giphyUrl('giphy|x1|downsized'),
        'https://media.giphy.com/media/x1/giphy.webp');
  });

  test('bodies keep their markdown structure', () {
    const code = 'Try:\n\n    val x = 1\n    val y = 2';
    expect(texts(bodySegments(code, const {}, 3)), ['T:$code']);
    const mixed = 'Try:\n\n    code here\n\nhttps://i.redd.it/a.jpg';
    expect(texts(bodySegments(mixed, const {}, 3)),
        ['T:Try:\n\n    code here', 'M:https://i.redd.it/a.jpg']);
  });
}
