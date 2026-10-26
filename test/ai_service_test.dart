import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/widgets/reddit_markdown.dart';
import 'package:luli_for_reddit/data/ai_service.dart';
import 'package:luli_for_reddit/models/comment.dart';
import 'package:luli_for_reddit/models/post.dart';

/// Ports of the Android app's AiChatUrlTest, AiCitationsTest and RtlTest.
void main() {
  group('chatUrl', () {
    test('base without version gets v1', () {
      expect(chatUrl('https://api.openai.com'),
          'https://api.openai.com/v1/chat/completions');
      expect(chatUrl('https://my-litellm:4000/'),
          'https://my-litellm:4000/v1/chat/completions');
    });

    test('base with version is used as is', () {
      expect(chatUrl('https://api.groq.com/openai/v1'),
          'https://api.groq.com/openai/v1/chat/completions');
      expect(chatUrl(' https://openrouter.ai/api/v1/ '),
          'https://openrouter.ai/api/v1/chat/completions');
      expect(chatUrl('https://example.com/v2'),
          'https://example.com/v2/chat/completions');
    });
  });

  group('citations', () {
    final post = Post.fromData({
      'id': 'p',
      'title': 'Battery life?',
      'subreddit': 'GalaxyWatch',
      'num_comments': 40,
    });
    Comment comment(String id, String author, int score, String body) =>
        Comment(
          id: id,
          fullname: 't1_$id',
          author: author,
          body: body,
          score: score,
          created: DateTime.fromMillisecondsSinceEpoch(0),
          depth: 0,
        );
    final comments = [
      comment('a', 'low', 1, 'Meh.'),
      comment('b', 'top', 90, 'Two days with AOD off.'),
      comment('c', 'mid', 20, 'One day with AOD on.'),
    ];

    test('comments are tagged most upvoted first', () {
      final t = AiService.buildCitedThread(post, comments, 10000);
      expect(t.refs.values.map((c) => c.author), ['top', 'mid', 'low']);
      expect(t.text.contains('[c1] [90] u/top: Two days with AOD off.'),
          isTrue);
      expect(t.included, 3);
    });

    test('only what fits is tagged and counted', () {
      final t = AiService.buildCitedThread(post, comments, 230);
      expect(t.included, lessThan(3));
      expect(t.loaded, 3);
      expect(t.refs.length, t.included);
    });

    test('citations become comment links, unknown tags are dropped', () {
      final t = AiService.buildCitedThread(post, comments, 10000);
      expect(
          AiService.linkCitations(
              'Most get two days [c1] [c2], one disagrees [c9].', t.refs),
          'Most get two days [u/top](ilay-comment:t1_b) '
          '[u/mid](ilay-comment:t1_c), one disagrees .');
    });
  });

  group('RTL', () {
    test('a Hebrew summary is RTL even with English words in it', () {
      expect(
          isMostlyRtl('TL;DR: המשתמשים ב-Reddit חושבים שהעדכון של iOS 27 '
              'פוגע בסוללה, ורובם ממליצים לחכות לגרסה הבאה.'),
          isTrue);
    });

    test('Arabic is RTL', () {
      expect(isMostlyRtl('يعتقد معظم المعلقين أن التحديث يستهلك البطارية'),
          isTrue);
    });

    test('English with a Hebrew word stays LTR', () {
      expect(
          isMostlyRtl(
              'People in the thread say שלום means both hello and goodbye.'),
          isFalse);
    });

    test('no letters stays LTR', () {
      expect(isMostlyRtl('123 — 456'), isFalse);
    });
  });
}
