import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/media_links.dart';
import 'package:luli_for_reddit/models/comment.dart';

void main() {
  test('a GIF-only comment resolves its giphy media (issue #13)', () {
    final c = Comment.fromChild({
      'kind': 't1',
      'data': {
        'id': 'c1',
        'name': 't1_c1',
        'author': 'mrsir1987',
        'body': '![gif](giphy|3o7btPCcdNniyf0ArS|downsized)',
        'score': 6100,
        'created_utc': 1700000000,
        'media_metadata': {
          'giphy|3o7btPCcdNniyf0ArS|downsized': {
            'status': 'valid',
            'e': 'AnimatedImage',
            'm': 'image/gif',
            's': {
              'y': 200,
              'gif': 'https://external-preview.redd.it/abc.gif?width=200&amp;height=200&amp;s=x',
              'mp4': 'https://external-preview.redd.it/abc.gif?format=mp4&amp;s=y',
              'x': 200,
            },
            't': 'giphy',
            'id': 'giphy|3o7btPCcdNniyf0ArS|downsized',
          },
          'emote|t5_2qh1i|1234': {
            'status': 'valid',
            'e': 'Image',
            's': {'u': 'https://reddit-econ.example/emote.png'},
          },
        },
      },
    }, 0);

    expect(c.media.keys, ['giphy|3o7btPCcdNniyf0ArS|downsized']);
    final split = splitMediaRefs(c.body, c.media);
    expect(split.text, isEmpty);
    expect(split.media.single.toString(),
        'https://external-preview.redd.it/abc.gif?width=200&height=200&s=x');
    expect(isImageUrl(split.media.single), isTrue);
    expect(isGifUrl(split.media.single), isTrue);
  });

  test('text around a media ref is kept; unknown refs are left alone', () {
    final split = splitMediaRefs('lol ![gif](giphy|a) and ![img](missing)',
        {'giphy|a': 'https://i.redd.it/a.gif'});
    expect(split.text, 'lol  and ![img](missing)');
    expect(split.media.single.toString(), 'https://i.redd.it/a.gif');
  });
}
