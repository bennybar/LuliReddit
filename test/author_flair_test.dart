import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/models/flair.dart';

void main() {
  test('richtext keeps text and emoji in order', () {
    final f = authorFlairOf({
      'author_flair_richtext': [
        {
          'e': 'emoji',
          'a': ':watch:',
          'u': 'https://emoji.redditmedia.com/w.png'
        },
        {'e': 'text', 't': ' Galaxy Watch Ultra '},
      ],
      'author_flair_text': ':watch: Galaxy Watch Ultra',
    })!;
    expect(f.parts, const [
      FlairPart(emojiUrl: 'https://emoji.redditmedia.com/w.png'),
      FlairPart(text: ' Galaxy Watch Ultra'),
    ]);
    expect(f.text, 'Galaxy Watch Ultra');
  });

  test('emoji-only flair is kept (it has images)', () {
    final f = authorFlairOf({
      'author_flair_richtext': [
        {'e': 'emoji', 'a': ':x:', 'u': 'https://e/x.png'},
      ],
      'author_flair_text': ':x:',
    })!;
    expect(f.parts, const [FlairPart(emojiUrl: 'https://e/x.png')]);
  });

  test('plain text loses its emoji codes', () {
    expect(authorFlairOf({'author_flair_text': ':mod: Moderator'})!.text,
        'Moderator');
  });

  test('no flair is null', () {
    expect(authorFlairOf({'author_flair_text': null}), isNull);
    expect(authorFlairOf({'author_flair_text': ':x:'}), isNull);
  });
}
