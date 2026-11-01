import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/models/flair.dart';

void main() {
  test('richtext keeps text and emoji in order', () {
    final f = flairOf({
      'author_flair_richtext': [
        {
          'e': 'emoji',
          'a': ':watch:',
          'u': 'https://emoji.redditmedia.com/w.png'
        },
        {'e': 'text', 't': ' Galaxy Watch Ultra '},
      ],
      'author_flair_text': ':watch: Galaxy Watch Ultra',
    }, 'author')!;
    expect(f.parts, const [
      FlairPart(emojiUrl: 'https://emoji.redditmedia.com/w.png'),
      FlairPart(text: ' Galaxy Watch Ultra'),
    ]);
    expect(f.text, 'Galaxy Watch Ultra');
  });

  test('emoji-only flair is kept (it has images)', () {
    final f = flairOf({
      'author_flair_richtext': [
        {'e': 'emoji', 'a': ':x:', 'u': 'https://e/x.png'},
      ],
      'author_flair_text': ':x:',
    }, 'author')!;
    expect(f.parts, const [FlairPart(emojiUrl: 'https://e/x.png')]);
  });

  test('plain text loses its emoji codes', () {
    expect(flairOf({'author_flair_text': ':mod: Moderator'}, 'author')!.text,
        'Moderator');
  });

  test('no flair is null', () {
    expect(flairOf({'author_flair_text': null}, 'author'), isNull);
    expect(flairOf({'author_flair_text': ':x:'}, 'author'), isNull);
  });

  test("a post's flair keeps its images (#56)", () {
    final f = flairOf({
      'link_flair_richtext': [
        {'e': 'emoji', 'a': ':a16:', 'u': 'https://emoji.redditmedia.com/a.png'},
        {'e': 'text', 't': ' Android 16'},
      ],
      'link_flair_text': ':a16: Android 16',
    }, 'link')!;
    expect(f.parts.first.emojiUrl, 'https://emoji.redditmedia.com/a.png');
    expect(f.text, 'Android 16');
  });

  test('plain flair text loses its emoji codes', () {
    String? plain(String t) => flairOf({'link_flair_text': t}, 'link')?.text;
    expect(plain(':Discussion: Discussion'), 'Discussion');
    expect(plain('Medieval Europe :castle:'), 'Medieval Europe');
    expect(plain(':q:  Help   :x_y-1: me'), 'Help me');
    expect(plain('OC'), 'OC');
    expect(plain('10:30 AM'), '10:30 AM');
    expect(plain(':star:'), isNull);
  });
}
